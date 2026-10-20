output "repository_urls" {
  description = "CI/CD와 쿠버네티스 매니페스트에서 쓸 이미지 경로"
  value       = module.ecr.repository_urls
}

output "registry_url" {
  description = "Jenkins의 ECR 로그인, GitOps overlays/aws 이미지 주소에 사용"
  value       = module.ecr.registry_url
}
