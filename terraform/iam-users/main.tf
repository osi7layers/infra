# 팀원 IAM 사용자와 역할별 그룹. 메인(terraform/)과 state를 분리해서, 메인을 destroy해도 팀원 계정은 남는다.
# 권한은 사용자가 아니라 그룹에 붙인다. kubectl 권한(EKS Access Entry)은 클러스터에 붙는 설정이라 메인 eks 모듈에 있다.
# 콘솔 비밀번호와 액세스 키는 state에 비밀이 남지 않도록 Terraform이 아니라 콘솔에서 발급한다.

data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id

  groups = ["infra-admin", "network", "k8s-operator", "cicd", "observability", "readonly", "qa-k6"]

  # AWS 관리형 정책 (그룹 -> 정책 ARN)
  managed_policies = {
    "network/vpc-read"       = { group = "network", arn = "arn:aws:iam::aws:policy/AmazonVPCReadOnlyAccess" }
    "network/route53"        = { group = "network", arn = "arn:aws:iam::aws:policy/AmazonRoute53FullAccess" }
    "k8s-operator/ecr-read"  = { group = "k8s-operator", arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly" }
    "k8s-operator/cw-read"   = { group = "k8s-operator", arn = "arn:aws:iam::aws:policy/CloudWatchReadOnlyAccess" }
    "observability/cw-read"  = { group = "observability", arn = "arn:aws:iam::aws:policy/CloudWatchReadOnlyAccess" }
    "observability/ec2-read" = { group = "observability", arn = "arn:aws:iam::aws:policy/AmazonEC2ReadOnlyAccess" }
    "readonly/readonly"      = { group = "readonly", arn = "arn:aws:iam::aws:policy/ReadOnlyAccess" }
  }

  # 직접 만든 정책 (그룹 -> 정책 이름). readonly는 ReadOnlyAccess에 EKS 조회가 들어 있어 eks-read가 필요 없다
  custom_policies = {
    "network/eks-read"       = { group = "network", policy = "eks-read" }
    "network/vpn-write"      = { group = "network", policy = "vpn-write" }
    "k8s-operator/eks-read"  = { group = "k8s-operator", policy = "eks-read" }
    "cicd/eks-read"          = { group = "cicd", policy = "eks-read" }
    "cicd/ecr-push"          = { group = "cicd", policy = "ecr-push" }
    "observability/eks-read" = { group = "observability", policy = "eks-read" }
    "qa-k6/ec2-start-stop"   = { group = "qa-k6", policy = "k6-ec2" }
  }

  policy_documents = {
    "eks-read"  = data.aws_iam_policy_document.eks_read.json
    "vpn-write" = data.aws_iam_policy_document.vpn_write.json
    "ecr-push"  = data.aws_iam_policy_document.ecr_push.json
    "k6-ec2"    = data.aws_iam_policy_document.k6_ec2.json
    "self-mfa"  = data.aws_iam_policy_document.self_mfa.json
  }
}

# ---------------------------------------------------------------- 비밀번호 정책 (계정 전체)
resource "aws_iam_account_password_policy" "this" {
  minimum_password_length        = 14
  require_lowercase_characters   = true
  require_uppercase_characters   = true
  require_numbers                = true
  require_symbols                = true
  allow_users_to_change_password = true
  password_reuse_prevention      = 24
  max_password_age               = 90
}

# ---------------------------------------------------------------- 그룹과 사용자
resource "aws_iam_group" "this" {
  for_each = toset(local.groups)

  name = "${var.project}-${each.key}"
}

resource "aws_iam_user" "this" {
  #checkov:skip=CKV_AWS_273:학습 프로젝트라 IAM Identity Center(SSO) 대신 IAM 사용자 + 그룹 권한 + MFA 등록(팀 규칙)으로 운영
  for_each = var.users

  name          = each.key
  force_destroy = true # 콘솔에서 만든 비밀번호, MFA, 액세스 키가 있어도 destroy 가능

  # 콘솔에서 액세스 키를 만들 때 넣은 설명은 사용자 태그(<키 ID> = 설명)로 저장된다. 지우지 않게 무시한다
  lifecycle {
    ignore_changes = [tags]
  }
}

resource "aws_iam_user_group_membership" "this" {
  for_each = var.users

  user   = aws_iam_user.this[each.key].name
  groups = [for g in each.value : aws_iam_group.this[g].name]
}

# ---------------------------------------------------------------- 정책 연결
resource "aws_iam_policy" "this" {
  for_each = local.policy_documents

  name   = "${var.project}-${each.key}"
  policy = each.value
}

# infra-admin은 Terraform이 VPC, EKS, IAM Role, ECR을 모두 만들어서 사실상 관리자 권한이 필요하다
resource "aws_iam_group_policy_attachment" "infra_admin" {
  #checkov:skip=CKV_AWS_274:IaC 담당이 VPC/EKS/IAM/ECR 전체를 Terraform으로 만들어 관리자 권한이 필요함. MFA 등록 필수(팀 규칙)
  group      = aws_iam_group.this["infra-admin"].name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_iam_group_policy_attachment" "managed" {
  for_each = local.managed_policies

  group      = aws_iam_group.this[each.value.group].name
  policy_arn = each.value.arn
}

resource "aws_iam_group_policy_attachment" "custom" {
  for_each = local.custom_policies

  group      = aws_iam_group.this[each.value.group].name
  policy_arn = aws_iam_policy.this[each.value.policy].arn
}

# 모든 그룹: 자기 비밀번호/MFA/액세스 키 관리
resource "aws_iam_group_policy_attachment" "self_mfa" {
  for_each = toset(local.groups) # 리소스가 아닌 고정 목록으로 반복해야 import 때도 키를 정할 수 있음

  group      = aws_iam_group.this[each.key].name
  policy_arn = aws_iam_policy.this["self-mfa"].arn
}

# ---------------------------------------------------------------- 서비스 계정 (사람이 아닌 프로그램용)
# 온프레미스의 Jenkins와 ArgoCD가 액세스 키로 쓴다. 팀원 그룹(local.groups)에 넣지 않는 이유는
# 자기 자격 증명 관리 정책(self-mfa)이 붙지 않게 하려고다. 액세스 키는 콘솔에서 발급해 CI/CD 담당에게 전달한다.
locals {
  service_users = {
    jenkins = { user = "${var.project}-jenkins-ecr-push", policy = "ecr-push" } # ECR push (Harbor와 이중 push)
    argocd  = { user = "${var.project}-argocd", policy = "eks-read" }           # EKS 원격 관리. kubectl 권한은 메인의 Access Entry
  }
}

resource "aws_iam_group" "service" {
  for_each = local.service_users

  name = "${var.project}-${each.key}"
}

resource "aws_iam_group_policy_attachment" "service" {
  for_each = local.service_users

  group      = aws_iam_group.service[each.key].name
  policy_arn = aws_iam_policy.this[each.value.policy].arn
}

resource "aws_iam_user" "service" {
  #checkov:skip=CKV_AWS_273:온프레미스 Jenkins·ArgoCD는 SSO를 쓸 수 없어 IAM 사용자(그룹 권한, 필요한 권한만)를 사용. 액세스 키는 주기적으로 교체
  for_each = local.service_users

  name          = each.value.user
  force_destroy = true # 콘솔에서 발급한 액세스 키가 있어도 destroy 가능

  # 액세스 키 설명 태그(<키 ID> = 설명)를 지우지 않게 무시한다
  lifecycle {
    ignore_changes = [tags]
  }
}

resource "aws_iam_user_group_membership" "service" {
  for_each = local.service_users

  user   = aws_iam_user.service[each.key].name
  groups = [aws_iam_group.service[each.key].name]
}

# ---------------------------------------------------------------- 정책 문서
# EKS 조회. aws eks update-kubeconfig에 eks:DescribeCluster가 필요하다 (kubectl 권한 자체는 Access Entry가 준다)
data "aws_iam_policy_document" "eks_read" {
  statement {
    sid       = "ReadClusters"
    actions   = ["eks:Describe*", "eks:List*"]
    resources = ["arn:aws:eks:${var.region}:${local.account_id}:*"]
  }

  # 클러스터 목록과 애드온 버전 조회는 특정 리소스에 붙지 않는 작업이라 "*"만 가능
  statement {
    sid       = "ListAll"
    actions   = ["eks:ListClusters", "eks:DescribeAddonVersions"]
    resources = ["*"]
  }
}

# 광렬: VPN 구성 (VGW, CGW, VPN Connection, 라우팅). 조회는 AmazonVPCReadOnlyAccess
data "aws_iam_policy_document" "vpn_write" {
  statement {
    actions = [
      "ec2:CreateVpnGateway", "ec2:DeleteVpnGateway", "ec2:AttachVpnGateway", "ec2:DetachVpnGateway",
      "ec2:CreateCustomerGateway", "ec2:DeleteCustomerGateway",
      "ec2:CreateVpnConnection", "ec2:DeleteVpnConnection", "ec2:ModifyVpnConnection",
      "ec2:ModifyVpnConnectionOptions", "ec2:ModifyVpnTunnelOptions", "ec2:ModifyVpnTunnelCertificate",
      "ec2:CreateVpnConnectionRoute", "ec2:DeleteVpnConnectionRoute",
      "ec2:EnableVgwRoutePropagation", "ec2:DisableVgwRoutePropagation",
      "ec2:CreateRoute", "ec2:ReplaceRoute", "ec2:DeleteRoute",
      "ec2:GetVpnConnectionDeviceTypes", "ec2:GetVpnConnectionDeviceSampleConfiguration",
      "ec2:CreateTags",
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.region]
    }
  }
}

# 지은(cicd 그룹)과 Jenkins: 프로젝트 리포지토리에만 push/pull. 로그인 토큰 발급(GetAuthorizationToken)은 AWS 구조상 리소스를 좁힐 수 없다
data "aws_iam_policy_document" "ecr_push" {
  statement {
    sid       = "EcrLogin"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid = "PushPullProjectRepos"
    actions = [
      "ecr:BatchCheckLayerAvailability", "ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer",
      "ecr:DescribeImages", "ecr:DescribeRepositories", "ecr:ListImages",
      "ecr:InitiateLayerUpload", "ecr:UploadLayerPart", "ecr:CompleteLayerUpload", "ecr:PutImage",
    ]
    resources = ["arn:aws:ecr:${var.region}:${local.account_id}:repository/${var.ecr_namespace}/*"]
  }
}

# 재학: 지정한 태그가 붙은 EC2(k6 부하 발생기)만 시작/중지
data "aws_iam_policy_document" "k6_ec2" {
  statement {
    actions   = ["ec2:StartInstances", "ec2:StopInstances"]
    resources = ["arn:aws:ec2:${var.region}:${local.account_id}:instance/*"]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/${var.k6_instance_tag.key}"
      values   = [var.k6_instance_tag.value]
    }
  }
}

# 자기 비밀번호, MFA, 액세스 키를 스스로 관리하는 권한 (MFA 등록은 팀 규칙으로 하고 정책으로 강제하지 않는다).
# MFA가 없으면 거부하는 Deny 문은 일부러 두지 않았다. aws login으로 받은 CLI 세션은 콘솔에서 MFA로 로그인했어도
# aws:MultiFactorAuthPresent=false로 표시되어, Deny가 있으면 Terraform을 포함한 모든 CLI 작업이 막힌다 (이 계정에서 확인).
data "aws_iam_policy_document" "self_mfa" {
  statement {
    sid       = "ViewAccountInfo"
    actions   = ["iam:GetAccountPasswordPolicy", "iam:ListVirtualMFADevices"]
    resources = ["*"]
  }

  statement {
    sid = "ManageOwnCredentials"
    actions = [
      "iam:ChangePassword", "iam:GetUser", "iam:GetLoginProfile",
      "iam:CreateAccessKey", "iam:DeleteAccessKey", "iam:ListAccessKeys", "iam:UpdateAccessKey",
      "iam:ListMFADevices", "iam:EnableMFADevice", "iam:ResyncMFADevice", "iam:DeactivateMFADevice",
      "iam:CreateVirtualMFADevice", "iam:DeleteVirtualMFADevice",
    ]
    resources = [
      "arn:aws:iam::${local.account_id}:user/$${aws:username}",
      "arn:aws:iam::${local.account_id}:mfa/*",
    ]
  }
}
