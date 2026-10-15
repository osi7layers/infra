output "cluster_name" {
  value = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  description = "API 서버 주소. kubeconfig는 aws eks update-kubeconfig --name <cluster_name> 로 만든다"
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_security_group_id" {
  value = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}

output "node_group_name" {
  value = aws_eks_node_group.this.node_group_name
}

output "lb_controller_role_arn" {
  description = "AWS Load Balancer Controller 역할 (kube-system/aws-load-balancer-controller에 Pod Identity로 연결됨)"
  value       = aws_iam_role.lb_controller.arn
}
