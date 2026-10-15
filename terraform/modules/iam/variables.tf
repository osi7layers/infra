variable "project" {
  type = string
}

variable "ecr_pull_policy_arn" {
  description = "노드(EC2)에 붙일 ECR Pull 정책"
  type        = string
}
