variable "project" {
  type = string
}

variable "repositories" {
  description = "ECR 리포지토리 이름 목록 (실제 이름은 '<namespace>/<이름>', 예: ecommerce/web)"
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
  description = "리포지토리마다 보관할 최근 이미지 수 (push 순서 기준, 초과분은 자동 삭제해 저장 비용 절감). 롤백할 버전은 이 범위 안에 있어야 함"
  type        = number
  default     = 10
}

variable "force_delete" {
  description = "true이면 이미지가 남아 있어도 destroy 가능. false면 이미지가 있는 리포지토리는 destroy가 거부된다"
  type        = bool
  default     = false
}

variable "namespace" {
  description = "ECR 리포지토리 이름 접두사. Harbor 프로젝트 이름과 같게 둔다 (예: ecommerce -> ecommerce/web)"
  type        = string
}
