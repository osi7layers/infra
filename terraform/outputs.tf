output "vpc_id" {
  value = module.network.vpc_id
}

output "public_subnet_ids" {
  value = module.network.public_subnet_ids
}

output "app_subnet_ids" {
  value = module.network.app_subnet_ids
}

output "alb_sg_id" {
  value = module.security.alb_sg_id
}

output "node_sg_id" {
  value = module.security.node_sg_id
}

output "ecr_repository_urls" {
  description = "CI/CD와 쿠버네티스 매니페스트에서 쓸 이미지 경로"
  value       = module.ecr.repository_urls
}

output "ci_user_name" {
  value = module.iam.ci_user_name
}

output "ecr_registry_url" {
  description = "Jenkins의 ECR 로그인, GitOps overlays/aws 이미지 주소에 사용"
  value       = module.ecr.registry_url
}

output "eks_cluster_name" {
  description = "aws eks update-kubeconfig --name <값> --region ap-northeast-2"
  value       = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  value = module.eks.cluster_endpoint
}
