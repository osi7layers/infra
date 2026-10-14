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
