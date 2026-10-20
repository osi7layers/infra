output "repository_urls" {
  description = "이름 -> 리포지토리 URL (CI/CD, 쿠버네티스 매니페스트의 이미지 경로)"
  value       = { for name, r in aws_ecr_repository.this : name => r.repository_url }
}

output "registry_url" {
  description = "docker login 대상, GitOps overlays/aws의 이미지 주소 앞부분"
  value       = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.name}.amazonaws.com"
}
