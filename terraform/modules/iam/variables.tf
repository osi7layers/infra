variable "project" {
  type = string
}

variable "ecr_namespace" {
  description = "노드가 Pull할 ECR 리포지토리 이름 접두사 (terraform/ecr의 namespace와 같게. 예: ecommerce -> ecommerce/*)"
  type        = string
}
