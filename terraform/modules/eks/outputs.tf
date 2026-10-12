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
