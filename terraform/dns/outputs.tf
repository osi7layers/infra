output "name_servers" {
  description = "콘솔에서 만든 영역의 네임서버 4개 (가비아 네임서버 설정과 같아야 함)"
  value       = data.aws_route53_zone.this.name_servers
}

output "zone_id" {
  description = "호스팅 영역 ID. 자동 갱신 도구(cert-manager의 hostedZoneID 등) 설정에 사용"
  value       = data.aws_route53_zone.this.zone_id
}

output "acme_user_name" {
  description = "인증서 자동 갱신용 IAM 사용자. 액세스 키는 콘솔에서 발급"
  value       = try(aws_iam_user.acme[0].name, null)
}
