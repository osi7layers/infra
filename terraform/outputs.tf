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

output "lb_controller_role_arn" {
  description = "AWS Load Balancer Controller 역할. Helm 설치 시 serviceAccount.name=aws-load-balancer-controller, clusterName·vpcId와 함께 사용"
  value       = module.eks.lb_controller_role_arn
}

output "container_insights_log_groups" {
  description = "Container Insights 로그 그룹. 지표는 CloudWatch 네임스페이스 ContainerInsights (Grafana에서 ClusterName = 클러스터 이름으로 조회)"
  value       = module.eks.container_insights_log_groups
}
