variable "region" {
  description = "AWS 리전 (메인 terraform과 동일)"
  type        = string
  default     = "ap-northeast-2"
}

variable "project" {
  description = "프로젝트 이름 (태그 접두사). 메인이 이 이름으로 EIP를 찾는다"
  type        = string
  default     = "osi7"
}

variable "nat_eip_count" {
  description = "고정 EIP 개수. 메인의 nat_gateway_count와 같게 둔다"
  type        = number
  default     = 1

  validation {
    condition     = var.nat_eip_count >= 1
    error_message = "nat_eip_count는 1 이상이어야 합니다."
  }
}
