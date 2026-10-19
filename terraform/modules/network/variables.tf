variable "project" {
  type = string
}

variable "vpc_cidr" {
  type = string
}

variable "azs" {
  type = list(string)
}

variable "public_subnet_cidrs" {
  type = list(string)
}

variable "app_subnet_cidrs" {
  type = list(string)
}

variable "nat_gateway_count" {
  description = "1 이상 AZ 개수 이하"
  type        = number

  validation {
    condition     = var.nat_gateway_count >= 1
    error_message = "nat_gateway_count는 1 이상이어야 합니다."
  }
}

variable "nat_eip_allocation_ids" {
  description = "NAT에 붙일 기존 EIP의 allocation ID (NAT 개수만큼). 비우면 모듈이 EIP를 만든다"
  type        = list(string)
  default     = []

  validation {
    condition     = length(var.nat_eip_allocation_ids) == 0 || length(var.nat_eip_allocation_ids) == var.nat_gateway_count
    error_message = "nat_eip_allocation_ids는 비우거나 nat_gateway_count와 개수가 같아야 합니다."
  }
}
