variable "region" {
  description = "AWS 리전 (메인 terraform과 동일)"
  type        = string
  default     = "ap-northeast-2"
}

variable "project" {
  description = "프로젝트 이름 (태그)"
  type        = string
  default     = "osi7"
}

variable "namespace" {
  description = "ECR 리포지토리 이름 접두사. Harbor 프로젝트 이름과 같게 둔다. 메인의 ecr_namespace(노드 Pull 범위)도 같게 둔다"
  type        = string
  default     = "ecommerce"
}

variable "repositories" {
  description = "ECR 리포지토리 이름 목록 (백엔드 4개 + 프론트엔드 web). 이름은 Harbor 리포지토리 이름과 맞춘다"
  type        = list(string)
  default     = ["auth", "product", "order", "promotion", "web"]
}

variable "image_tag_mutability" {
  description = "IMMUTABLE이면 같은 태그 재푸시 불가. CI/CD가 latest를 덮어쓰면 MUTABLE로 변경"
  type        = string
  default     = "IMMUTABLE"
}

variable "keep_image_count" {
  description = "리포지토리마다 보관할 최근 이미지 수 (push 순서 기준). 롤백할 버전은 최근 10번 push 안에 있어야 함"
  type        = number
  default     = 10
}

variable "force_delete" {
  description = "true이면 이미지가 있어도 destroy 가능. 상시 루트라 false로 두어 실수로 이미지를 지우지 않게 한다"
  type        = bool
  default     = false
}
