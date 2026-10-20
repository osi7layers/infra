# ---------------------------------------------------------------- 쿠버네티스 노드(EC2) 역할
# EKS 관리형 노드 그룹이 이 역할을 쓴다 (eks 모듈의 node_role_arn). 노드 등록, VPC CNI, ECR Pull 권한을 준다.
data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "node" {
  name               = "${var.project}-node-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

# 프로젝트 ECR Pull 정책. 리포지토리는 상시 루트 terraform/ecr에 있어서, 그 state를 읽지 않도록
# Push 정책(terraform/iam-users)과 같이 <namespace>/* 이름으로 범위를 정한다.
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

data "aws_iam_policy_document" "ecr_pull" {
  # 로그인 토큰 발급은 특정 리포지토리에 걸 수 없어서 Resource "*"가 필수다.
  statement {
    sid       = "GetAuthorizationToken"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid = "PullImages"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
    ]
    resources = ["arn:aws:ecr:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:repository/${var.ecr_namespace}/*"]
  }
}

resource "aws_iam_policy" "ecr_pull" {
  name        = "${var.project}-ecr-pull"
  description = "ECR 이미지 Pull 전용"
  policy      = data.aws_iam_policy_document.ecr_pull.json
}

resource "aws_iam_role_policy_attachment" "node_ecr_pull" {
  role       = aws_iam_role.node.name
  policy_arn = aws_iam_policy.ecr_pull.arn
}

# EKS 관리형 노드 그룹에 필요한 AWS 관리형 정책 (노드 등록, VPC CNI)
resource "aws_iam_role_policy_attachment" "node_eks_worker" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "node_eks_cni" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

# EKS 시스템 이미지(aws-node, kube-proxy, coredns)는 AWS 소유 ECR에 있어서 위의 프로젝트 전용 Pull 정책으로는 받을 수 없다.
# 이 정책이 없으면 VPC CNI가 뜨지 못해 노드가 NotReady로 남는다 (NodeCreationFailure).
resource "aws_iam_role_policy_attachment" "node_ecr_pull_only" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPullOnly"
}

# Jenkins(ECR push)와 ArgoCD용 IAM 사용자는 terraform/iam-users에 있다. 여기 두면 메인을 destroy할 때마다
# 사용자와 액세스 키가 지워져 Jenkins·ArgoCD에 키를 다시 넣어야 한다.

# ---------------------------------------------------------------- EKS 클러스터(컨트롤 플레인) 역할
data "aws_iam_policy_document" "eks_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eks_cluster" {
  name               = "${var.project}-eks-cluster-role"
  assume_role_policy = data.aws_iam_policy_document.eks_assume.json
}

resource "aws_iam_role_policy_attachment" "eks_cluster" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}
