output "node_instance_profile_name" {
  description = "자체 설치형(EC2) 노드용 instance profile. EKS 관리형 노드 그룹은 node_role_arn을 사용하므로 현재는 쓰이지 않음"
  value       = aws_iam_instance_profile.node.name
}

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
