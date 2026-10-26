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
  #checkov:skip=CKV_AWS_339:checkov의 지원 버전 목록에 1.36이 아직 없어서 생긴 오탐. AWS 기준 표준 지원 중 (2027-08까지)
  name     = var.cluster_name
  version  = var.kubernetes_version
  role_arn = var.cluster_role_arn

  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  # 비워 두면 EKS가 VPC 대역을 보고 자동으로 고른다. 온프레미스와 VPN으로 이을 때 겹치지 않게 명시한다
  kubernetes_network_config {
    service_ipv4_cidr = var.service_ipv4_cidr
  }

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

  # aws-auth ConfigMap과 Access Entry 둘 다 허용.
  # 생성한 사람(Terraform 실행자)에게 자동으로 관리자를 주지 않고, 관리자도 access_entries에 명시한다.
  # (자동 부여와 Access Entry가 같은 사용자로 겹치면 생성이 실패하고, 누가 apply했는지에 따라 권한이 달라지지 않게 하려고)
  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = false
  }

  depends_on = [aws_cloudwatch_log_group.cluster]
}

# ---------------------------------------------------------------- 노드 그룹
# 시작 템플릿: IMDSv2 강제, EBS 암호화, 노드 SG + 클러스터 SG 부착
data "aws_default_tags" "this" {}

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

  # provider default_tags는 시작 템플릿 자체에만 붙고, 이 템플릿으로 뜨는 인스턴스·볼륨에는 전달되지 않는다.
  # Project 태그가 있어야 Cost Explorer 비용 할당 태그로 노드 비용을 모을 수 있어서 직접 넣는다.
  tag_specifications {
    resource_type = "instance"
    tags          = merge(data.aws_default_tags.this.tags, { Name = "${var.cluster_name}-node" })
  }

  tag_specifications {
    resource_type = "volume"
    tags          = merge(data.aws_default_tags.this.tags, { Name = "${var.cluster_name}-node" })
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

# ---------------------------------------------------------------- 팀원 kubectl 권한 (EKS Access Entry)
# IAM 사용자는 terraform/iam-users가 만든다. 사용자가 없으면 Access Entry 생성이 실패하므로 iam-users를 먼저 apply한다.
# 클러스터 관리자(명호)도 여기서 준다. 클러스터 생성자 자동 관리자는 꺼 두었다 (access_config 참고).
resource "aws_eks_access_entry" "this" {
  for_each = var.access_entries

  cluster_name  = aws_eks_cluster.this.name
  principal_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:user/${each.key}"
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "this" {
  for_each = var.access_entries

  cluster_name  = aws_eks_cluster.this.name
  principal_arn = aws_eks_access_entry.this[each.key].principal_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/${each.value.policy}"

  # namespaces가 비어 있으면 클러스터 전체, 있으면 그 네임스페이스에만 적용
  access_scope {
    type       = length(each.value.namespaces) > 0 ? "namespace" : "cluster"
    namespaces = length(each.value.namespaces) > 0 ? each.value.namespaces : null
  }
}

# 기본 정책에 더해 특정 네임스페이스에만 주는 정책 (예: 클러스터 전체 View + 특정 네임스페이스 Edit)
locals {
  extra_access_policies = merge([
    for user, e in var.access_entries : {
      for policy, namespaces in e.extra_policies : "${user}/${policy}" => {
        user       = user
        policy     = policy
        namespaces = namespaces
      }
    }
  ]...)
}

resource "aws_eks_access_policy_association" "extra" {
  for_each = local.extra_access_policies

  cluster_name  = aws_eks_cluster.this.name
  principal_arn = aws_eks_access_entry.this[each.value.user].principal_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/${each.value.policy}"

  access_scope {
    type       = "namespace"
    namespaces = each.value.namespaces
  }
}

# ---------------------------------------------------------------- AWS Load Balancer Controller 권한 (Pod Identity)
# 컨트롤러 자체는 Helm으로 kube-system에 설치한다 (Terraform 밖). 여기서는 그 서비스 계정이 쓸 AWS 권한만 만든다.
# 진입 ALB(Ingress → APISIX)를 이 컨트롤러가 만들고 지운다.
data "aws_iam_policy_document" "pod_identity_assume" {
  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"]

    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lb_controller" {
  name               = "${var.project}-aws-load-balancer-controller"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_assume.json
}

resource "aws_iam_policy" "lb_controller" {
  #checkov:skip=CKV_AWS_355:AWS 공식 정책 그대로. 만들 리소스의 ARN을 미리 알 수 없어 "*"를 쓰고, 생성·삭제는 elbv2.k8s.aws/cluster 태그 조건으로 제한함
  #checkov:skip=CKV_AWS_290:위와 같음
  #checkov:skip=CKV_AWS_289:위와 같음
  # 출처: kubernetes-sigs/aws-load-balancer-controller v3.6.0 docs/install/iam_policy.json (수정 없음).
  # 설치하는 컨트롤러 버전을 올리면 같은 버전의 파일로 바꾼다.
  name   = "${var.project}-aws-load-balancer-controller"
  policy = file("${path.module}/policies/aws-load-balancer-controller.json")
}

resource "aws_iam_role_policy_attachment" "lb_controller" {
  role       = aws_iam_role.lb_controller.name
  policy_arn = aws_iam_policy.lb_controller.arn
}

resource "aws_eks_pod_identity_association" "lb_controller" {
  cluster_name    = aws_eks_cluster.this.name
  namespace       = "kube-system"
  service_account = "aws-load-balancer-controller"
  role_arn        = aws_iam_role.lb_controller.arn
}

# ---------------------------------------------------------------- Cluster Autoscaler 권한 (Pod Identity)
# KEDA/HPA로 Pod가 늘다가 노드가 모자라면 Pending이 되므로, 노드 그룹(ASG)의 desired 수를 min~max 안에서 조정한다.
# 컨트롤러 설치(Helm, kube-system/cluster-autoscaler, autoDiscovery.clusterName = 클러스터 이름)는 Terraform 밖이다.
# 관리형 노드 그룹의 ASG에는 EKS가 k8s.io/cluster-autoscaler/<클러스터> = owned 태그를 자동으로 붙이므로,
# 개수 변경·인스턴스 종료는 그 태그가 있는 ASG로만 제한한다. 노드 그룹은 desired_size 변경을 무시한다 (위 lifecycle).
resource "aws_iam_role" "cluster_autoscaler" {
  name               = "${var.project}-cluster-autoscaler"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_assume.json
}

data "aws_iam_policy_document" "cluster_autoscaler" {
  #checkov:skip=CKV_AWS_356:ASG 이름은 EKS가 자동으로 붙여 미리 알 수 없어 "*"를 쓰고, 변경 작업은 k8s.io/cluster-autoscaler/<클러스터> = owned 태그 조건으로 제한함. 조회 작업은 리소스 지정 불가
  # 출처: kubernetes/autoscaler cluster-autoscaler/cloudprovider/aws/README.md (최소 권한 예시)
  statement {
    sid = "ScaleOwnedNodeGroups"
    actions = [
      "autoscaling:SetDesiredCapacity",
      "autoscaling:TerminateInstanceInAutoScalingGroup",
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/k8s.io/cluster-autoscaler/${var.cluster_name}"
      values   = ["owned"]
    }
  }

  # 조회 작업은 특정 리소스에 걸 수 없어서 "*"
  statement {
    sid = "Describe"
    actions = [
      "autoscaling:DescribeAutoScalingGroups",
      "autoscaling:DescribeAutoScalingInstances",
      "autoscaling:DescribeLaunchConfigurations",
      "autoscaling:DescribeScalingActivities",
      "autoscaling:DescribeTags",
      "ec2:DescribeImages",
      "ec2:DescribeInstanceTypes",
      "ec2:DescribeLaunchTemplateVersions",
      "ec2:GetInstanceTypesFromInstanceRequirements",
      "eks:DescribeNodegroup",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "cluster_autoscaler" {
  name   = "cluster-autoscaler"
  role   = aws_iam_role.cluster_autoscaler.id
  policy = data.aws_iam_policy_document.cluster_autoscaler.json
}

resource "aws_eks_pod_identity_association" "cluster_autoscaler" {
  cluster_name    = aws_eks_cluster.this.name
  namespace       = "kube-system"
  service_account = "cluster-autoscaler"
  role_arn        = aws_iam_role.cluster_autoscaler.arn
}

# ---------------------------------------------------------------- Container Insights (노드·Pod 지표, 컨테이너 로그 -> CloudWatch)
# amazon-cloudwatch-observability 애드온이 CloudWatch 에이전트와 Fluent Bit를 설치한다 (amazon-cloudwatch 네임스페이스).
# 온프레미스 Grafana는 이 지표와 로그를 CloudWatch 데이터 소스로 조회한다 (조회 권한은 iam-users의 osi7-grafana-read).
# 로그 그룹을 에이전트가 만들게 두면 보관 기간이 무기한이고 Terraform 밖이라 destroy해도 남으므로 여기서 먼저 만든다.
resource "aws_cloudwatch_log_group" "container_insights" {
  #checkov:skip=CKV_AWS_338:학습 프로젝트라 비용을 위해 30일만 보관
  #checkov:skip=CKV_AWS_158:로그 그룹 KMS 암호화는 비용 대비 효과가 낮아 생략
  for_each = toset(["application", "dataplane", "host", "performance"])

  name              = "/aws/containerinsights/${var.cluster_name}/${each.key}"
  retention_in_days = var.log_retention_days
}

resource "aws_iam_role" "cloudwatch_agent" {
  name               = "${var.project}-cloudwatch-agent"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_assume.json
}

resource "aws_iam_role_policy_attachment" "cloudwatch_agent" {
  role       = aws_iam_role.cloudwatch_agent.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_eks_addon" "cloudwatch_observability" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "amazon-cloudwatch-observability"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  # 애드온 기본값(monitorAllServices = true)은 모든 Pod에 OpenTelemetry 에이전트(Application Signals)를 넣는다 (2026-10-26 v6.7.0에서 확인).
  # 앱(Java)에 JAVA_TOOL_OPTIONS로 에이전트가 붙어 온프렘과 성능 비교가 달라지고 트레이스 요금이 생기므로 끈다.
  # 앱 지표는 Container Insights와 Prometheus 수집으로 본다. 이미 뜬 Pod는 재시작해야 에이전트가 빠진다
  configuration_values = jsonencode({
    manager = { applicationSignals = { autoMonitor = { monitorAllServices = false } } }
  })

  # 에이전트와 Fluent Bit가 같은 서비스 계정을 쓴다
  pod_identity_association {
    service_account = "cloudwatch-agent"
    role_arn        = aws_iam_role.cloudwatch_agent.arn
  }

  depends_on = [
    aws_eks_addon.this, # Pod Identity 에이전트가 먼저 있어야 권한을 받는다
    aws_cloudwatch_log_group.container_insights,
    aws_iam_role_policy_attachment.cloudwatch_agent,
  ]
}

# ---------------------------------------------------------------- EBS CSI 드라이버 (PVC -> EBS 볼륨)
# PVC마다 드라이버가 EBS 볼륨을 만들고 지운다. 쿠폰 Redis용으로 추가했지만 쿠폰은 온프레미스에서만 처리하기로 해서(2026-10-22)
# 지금 AWS에서 PVC를 쓰는 앱은 없다. 비용이 없어서 이후 PVC가 필요할 때를 위해 남겨 둔다.
# StorageClass(gp3, 암호화, 기본값)는 쿠버네티스 리소스라 scripts/install-controllers.sh가 만든다 (이 루트에는 쿠버네티스 provider가 없음).
# 드라이버가 만든 볼륨은 Terraform state에 없어서 destroy가 지우지 않는다. 내리기 전에 PVC를 지워 볼륨을 먼저 없앤다 (CLAUDE.md 내리는 순서).
resource "aws_iam_role" "ebs_csi" {
  name               = "${var.project}-ebs-csi-driver"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_assume.json
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  role       = aws_iam_role.ebs_csi.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

resource "aws_eks_addon" "ebs_csi" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "aws-ebs-csi-driver"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  # 드라이버가 만드는 볼륨에도 provider 기본 태그(Project 등)를 붙인다. 비용 할당 태그 집계와 내리기 전 남은 볼륨 확인에 쓴다
  configuration_values = jsonencode({
    controller = { extraVolumeTags = data.aws_default_tags.this.tags }
  })

  pod_identity_association {
    service_account = "ebs-csi-controller-sa"
    role_arn        = aws_iam_role.ebs_csi.arn
  }

  depends_on = [
    aws_eks_addon.this, # Pod Identity 에이전트가 먼저 있어야 권한을 받는다
    aws_iam_role_policy_attachment.ebs_csi,
  ]
}
