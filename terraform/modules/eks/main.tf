# ---------------------------------------------------------------- Secrets 암호화 키
data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "secrets_key" {
  #checkov:skip=CKV_AWS_109:KMS 키 정책의 표준 형태(계정 루트 위임). 실제 접근은 IAM 정책으로 제한
  #checkov:skip=CKV_AWS_111:위와 같음
  #checkov:skip=CKV_AWS_356:키 정책에서 resource "*"는 이 키 자신을 뜻함
  # 계정 루트에 위임: 이후 IAM 정책으로 접근 제어한다
  statement {
    sid       = "EnableIAMPolicies"
    actions   = ["kms:*"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }
}

resource "aws_kms_key" "secrets" {
  description             = "${var.cluster_name} Kubernetes Secrets 암호화"
  enable_key_rotation     = true
  deletion_window_in_days = 7
  policy                  = data.aws_iam_policy_document.secrets_key.json
}

# ---------------------------------------------------------------- 컨트롤 플레인 로그
resource "aws_cloudwatch_log_group" "cluster" {
  #checkov:skip=CKV_AWS_338:학습 프로젝트라 비용을 위해 30일만 보관
  #checkov:skip=CKV_AWS_158:로그 그룹 KMS 암호화는 비용 대비 효과가 낮아 생략
  name              = "/aws/eks/${var.cluster_name}/cluster"
  retention_in_days = var.log_retention_days
}

# ---------------------------------------------------------------- 클러스터
resource "aws_eks_cluster" "this" {
  name     = var.cluster_name
  version  = var.kubernetes_version
  role_arn = var.cluster_role_arn

  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  vpc_config {
    subnet_ids              = var.subnet_ids
    endpoint_private_access = true
    endpoint_public_access  = length(var.public_access_cidrs) > 0
    public_access_cidrs     = length(var.public_access_cidrs) > 0 ? var.public_access_cidrs : null
  }

  encryption_config {
    resources = ["secrets"]

    provider {
      key_arn = aws_kms_key.secrets.arn
    }
  }

  # aws-auth ConfigMap과 Access Entry 둘 다 허용. 생성한 사람은 자동으로 관리자
  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }

  depends_on = [aws_cloudwatch_log_group.cluster]
}

# ---------------------------------------------------------------- 노드 그룹
# 시작 템플릿: IMDSv2 강제, EBS 암호화, 노드 SG + 클러스터 SG 부착
resource "aws_launch_template" "node" {
  name_prefix = "${var.cluster_name}-node-"

  vpc_security_group_ids = [
    var.node_sg_id,
    aws_eks_cluster.this.vpc_config[0].cluster_security_group_id,
  ]

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1 # 파드가 노드 IAM 권한(IMDS)을 훔쳐 쓰지 못하게 한다. 파드 권한은 Pod Identity/IRSA로 부여
  }

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size = var.node_disk_size_gb
      volume_type = "gp3"
      encrypted   = true
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags          = { Name = "${var.cluster_name}-node" }
  }
}

resource "aws_eks_node_group" "this" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${var.cluster_name}-default"
  node_role_arn   = var.node_role_arn
  subnet_ids      = var.subnet_ids

  ami_type       = "AL2023_x86_64_STANDARD"
  instance_types = var.node_instance_types

  scaling_config {
    desired_size = var.node_desired_size
    min_size     = var.node_min_size
    max_size     = var.node_max_size
  }

  launch_template {
    id      = aws_launch_template.node.id
    version = aws_launch_template.node.latest_version
  }

  update_config {
    max_unavailable = 1
  }

  # 오토스케일러나 수동 조정으로 바뀐 개수를 terraform이 되돌리지 않게 한다
  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }
}

# ---------------------------------------------------------------- 애드온 (노드가 생긴 뒤에 설치)
resource "aws_eks_addon" "this" {
  for_each = toset(["vpc-cni", "kube-proxy", "coredns", "eks-pod-identity-agent"])

  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = each.value
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [aws_eks_node_group.this]
}
