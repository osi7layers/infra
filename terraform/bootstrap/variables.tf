variable "region" {
  description = "AWS 리전 (메인 terraform과 동일)"
  type        = string
  default     = "ap-northeast-2"
}

variable "project" {
  description = "프로젝트 이름 (버킷 이름 접두사, 태그)"
  type        = string
  default     = "osi7"
}

variable "noncurrent_version_days" {
  description = "state 이전 버전을 보관할 일수. 지나면 자동 삭제"
  type        = number
  default     = 90
}
