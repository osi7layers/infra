variable "project" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "route_table_ids" {
  description = "온프레미스 경로를 전파할 라우트 테이블 (network 모듈의 app 라우트 테이블)"
  type        = list(string)
}
