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

# Pull 정책(노드용)은 메인의 iam 모듈에, Push 정책(Jenkins, cicd 그룹)은 terraform/iam-users에 있다.
# 이 모듈은 상시 루트 terraform/ecr이 쓰므로, 여기서 정책을 만들면 메인 destroy와 생명 주기가 달라진다.

# ---------------------------------------------------------------- 레지스트리 주소 (Jenkins 로그인, GitOps 이미지 경로용)
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
