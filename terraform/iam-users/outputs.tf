output "console_signin_url" {
  description = "팀원 콘솔 로그인 주소"
  value       = "https://${local.account_id}.signin.aws.amazon.com/console"
}

output "user_arns" {
  description = "메인 eks_access_entries의 키와 같은 사용자 이름 -> ARN"
  value       = { for k, u in aws_iam_user.this : k => u.arn }
}

output "group_names" {
  value = [for g in aws_iam_group.this : g.name]
}

output "service_user_names" {
  description = "Jenkins·ArgoCD·Grafana용 사용자. 액세스 키는 콘솔에서 발급해 각 담당에게 전달"
  value       = { for k, u in aws_iam_user.service : k => u.name }
}

output "grafana_role_arn" {
  description = "Grafana CloudWatch 데이터 소스의 Assume Role ARN에 넣는 값"
  value       = aws_iam_role.grafana.arn
}
