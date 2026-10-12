# ---------------------------------------------------------------- 쿠버네티스 노드(EC2) 역할
# 노드가 ECR에서 이미지를 Pull 할 수 있게 한다. compute 모듈이 instance profile을 사용한다.
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

resource "aws_iam_role_policy_attachment" "node_ecr_pull" {
  role       = aws_iam_role.node.name
  policy_arn = var.ecr_pull_policy_arn
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

# EKS 시스템 이미지(aws-node, kube-proxy, coredns)는 AWS 소유 ECR에 있어서 위의 osi-shop 전용 Pull 정책으로는 받을 수 없다.
# 이 정책이 없으면 VPC CNI가 뜨지 못해 노드가 NotReady로 남는다 (NodeCreationFailure).
resource "aws_iam_role_policy_attachment" "node_ecr_pull_only" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPullOnly"
}

resource "aws_iam_instance_profile" "node" {
  name = "${var.project}-node-profile"
  role = aws_iam_role.node.name
}

# ---------------------------------------------------------------- Jenkins의 ECR Push 권한
# 정책은 사용자가 아니라 그룹에 붙인다 (권한 관리를 한 곳에서 하기 위해).
resource "aws_iam_group" "ecr_push" {
  count = var.create_ci_user ? 1 : 0

  name = "${var.project}-ecr-push"
}

resource "aws_iam_group_policy_attachment" "ecr_push" {
  count = var.create_ci_user ? 1 : 0

  group      = aws_iam_group.ecr_push[0].name
  policy_arn = var.ecr_push_policy_arn
}

resource "aws_iam_user" "ci" {
  #checkov:skip=CKV_AWS_273:온프레미스 Jenkins는 SSO를 쓸 수 없어 IAM 사용자(Push 전용, 그룹 권한)를 사용. 액세스 키는 주기적으로 교체
  count = var.create_ci_user ? 1 : 0

  name = "${var.project}-jenkins-ecr-push"
}

resource "aws_iam_user_group_membership" "ci" {
  count = var.create_ci_user ? 1 : 0

  user   = aws_iam_user.ci[0].name
  groups = [aws_iam_group.ecr_push[0].name]
}

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
