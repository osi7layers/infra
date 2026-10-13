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
