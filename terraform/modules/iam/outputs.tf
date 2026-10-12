output "node_role_name" {
  value = aws_iam_role.node.name
}

output "node_role_arn" {
  description = "EKS 관리형 노드 그룹에 붙일 역할"
  value       = aws_iam_role.node.arn
}

output "eks_cluster_role_arn" {
  value = aws_iam_role.eks_cluster.arn
}

output "ci_user_name" {
  description = "액세스 키는 콘솔에서 발급해 Jenkins Credentials에 등록"
  value       = try(aws_iam_user.ci[0].name, null)
}
