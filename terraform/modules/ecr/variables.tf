variable "project" {
  type = string
}

variable "repositories" {
  description = "ECR 리포지토리 이름 목록 (실제 이름은 '<project>/<이름>')"
  type        = list(string)
}

variable "image_tag_mutability" {
  description = "IMMUTABLE이면 같은 태그로 재푸시 불가(latest 재사용 불가). 커밋 해시 태그를 쓰는 전제"
  type        = string
  default     = "IMMUTABLE"

  validation {
    condition     = contains(["MUTABLE", "IMMUTABLE"], var.image_tag_mutability)
    error_message = "MUTABLE 또는 IMMUTABLE만 가능합니다."
  }
}

variable "keep_image_count" {
  description = "리포지토리마다 보관할 최근 이미지 수 (초과분은 자동 삭제해 저장 비용 절감)"
  type        = number
  default     = 30
}

variable "force_delete" {
  description = "true이면 이미지가 남아 있어도 destroy 가능 (재구축 리허설용). 운영에서는 false"
  type        = bool
  default     = true
}

variable "namespace" {
  description = "ECR 리포지토리 이름 접두사. Harbor 프로젝트 이름과 같게 둔다 (예: osi-shop -> osi-shop/frontend)"
  type        = string
}
