resource "aws_ecr_repository" "this" {
  for_each = toset(var.repositories)

  name                 = "${var.namespace}/${each.value}"
  image_tag_mutability = var.image_tag_mutability
  force_delete         = var.force_delete

  image_scanning_configuration {
    scan_on_push = true
  }

  # kms_key를 생략하면 AWS 관리형 키(aws/ecr)를 쓴다. 별도 키 비용이 없다.
  encryption_configuration {
    encryption_type = "KMS"
  }
}

resource "aws_ecr_lifecycle_policy" "this" {
  for_each = aws_ecr_repository.this

  repository = each.value.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "최근 ${var.keep_image_count}개만 보관"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = var.keep_image_count
      }
      action = { type = "expire" }
    }]
  })
}

# ---------------------------------------------------------------- IAM 정책 (Pull / Push)
locals {
  repository_arns = [for r in aws_ecr_repository.this : r.arn]

  pull_actions = [
    "ecr:BatchCheckLayerAvailability",
    "ecr:BatchGetImage",
    "ecr:GetDownloadUrlForLayer",
  ]

  push_actions = [
    "ecr:CompleteLayerUpload",
    "ecr:InitiateLayerUpload",
    "ecr:PutImage",
    "ecr:UploadLayerPart",
  ]
}

data "aws_iam_policy_document" "pull" {
  # 로그인 토큰 발급은 특정 리포지토리에 걸 수 없어서 Resource "*"가 필수다.
  statement {
    sid       = "GetAuthorizationToken"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid       = "PullImages"
    actions   = local.pull_actions
    resources = local.repository_arns
  }
}

data "aws_iam_policy_document" "push" {
  statement {
    sid       = "GetAuthorizationToken"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid       = "PushAndPullImages"
    actions   = concat(local.pull_actions, local.push_actions)
    resources = local.repository_arns
  }
}

resource "aws_iam_policy" "pull" {
  name        = "${var.project}-ecr-pull"
  description = "ECR 이미지 Pull 전용"
  policy      = data.aws_iam_policy_document.pull.json
}

resource "aws_iam_policy" "push" {
  name        = "${var.project}-ecr-push"
  description = "ECR 이미지 Push(및 Pull)"
  policy      = data.aws_iam_policy_document.push.json
}

# ---------------------------------------------------------------- 레지스트리 주소 (Jenkins 로그인, GitOps 이미지 경로용)
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
