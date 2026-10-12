variable "project" {
  type = string
}

variable "ecr_pull_policy_arn" {
  description = "노드(EC2)에 붙일 ECR Pull 정책"
  type        = string
}

variable "ecr_push_policy_arn" {
  description = "Jenkins가 쓸 ECR Push 정책"
  type        = string
}

variable "create_ci_user" {
  description = "Jenkins용 IAM 사용자 생성 여부. 액세스 키는 코드가 아니라 콘솔에서 발급한다(state에 비밀이 남지 않게)"
  type        = bool
  default     = true
}
