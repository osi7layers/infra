variable "project" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "node_service_port_from" {
  description = "ALB가 APISIX Pod로 보내는 포트 범위 시작 (target-type ip, APISIX gateway 9080)"
  type        = number
}

variable "node_service_port_to" {
  description = "ALB가 Node로 보내는 서비스 포트 범위 끝"
  type        = number
}
