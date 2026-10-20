# ECR 리포지토리 (<namespace>/<이름>). Jenkins가 Harbor와 같은 이미지를 같은 이름·태그로 push한다.
# 메인에 두면 테스트 후 destroy할 때마다 push한 이미지가 지워지므로 메인과 따로 둔다.
# 메인 노드의 Pull 정책은 <namespace>/* 범위라 이 state를 읽지 않고, Push 정책은 terraform/iam-users에 있다.
# 비용은 저장 용량만 나간다 (GB당 월 $0.10, 시간당 요금 없음).

module "ecr" {
  source = "../modules/ecr"

  project              = var.project
  namespace            = var.namespace
  repositories         = var.repositories
  image_tag_mutability = var.image_tag_mutability
  keep_image_count     = var.keep_image_count
  force_delete         = var.force_delete
}

# 메인 state에 있던 리포지토리(2026-10-20 메인에서 -target으로 생성)를 지우지 않고 그대로 가져온다. 첫 apply 후에는 지워도 된다.
# 리포지토리를 새로 추가할 때는 import할 대상이 없어 plan이 실패하므로, 그 전에 이 블록을 지운다.
import {
  for_each = toset(var.repositories)
  to       = module.ecr.aws_ecr_repository.this[each.value]
  id       = "${var.namespace}/${each.value}"
}

import {
  for_each = toset(var.repositories)
  to       = module.ecr.aws_ecr_lifecycle_policy.this[each.value]
  id       = "${var.namespace}/${each.value}"
}
