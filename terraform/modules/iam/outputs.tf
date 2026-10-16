output "node_role_arn" {
  description = "EKS 관리형 노드 그룹에 붙일 역할"
  value       = aws_iam_role.node.arn
}

output "eks_cluster_role_arn" {
  value = aws_iam_role.eks_cluster.arn
}
