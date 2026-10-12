variable "project" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "onprem_cidr" {
  description = "온프레미스 대역. VPN으로 들어오는 관리/DB 접근을 허용할 때 사용"
  type        = string
}

variable "db_port" {
  description = "DB 접속 포트 (MySQL 3306)"
  type        = number
}

variable "node_service_port_from" {
  description = "ALB가 Node로 보내는 서비스 포트 범위 시작 (NodePort 기본 30000-32767)"
  type        = number
}

variable "node_service_port_to" {
  description = "ALB가 Node로 보내는 서비스 포트 범위 끝"
  type        = number
}
