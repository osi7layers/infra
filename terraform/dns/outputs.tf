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

output "acm_certificate_arn" {
  description = "AWS 쪽 ALB HTTPS 리스너용 인증서. Ingress annotation alb.ingress.kubernetes.io/certificate-arn에 넣는다"
  value       = aws_acm_certificate_validation.aws_ingress.certificate_arn
}

output "service_records" {
  description = "서비스 레코드 (이름, 쪽, 가중치). 가중치가 null이면 단순 레코드"
  value = concat(
    [for r in aws_route53_record.onprem_weighted : { name = r.name, side = "onprem", weight = var.onprem_weight }],
    [for r in aws_route53_record.aws_weighted : { name = r.name, side = "aws", weight = var.aws_weight }],
    [for r in aws_route53_record.onprem_only : { name = r.name, side = "onprem", weight = null }],
  )
}

output "aws_lb_dns_name" {
  description = "태그로 찾은 AWS 쪽 LB 주소 (aws_ingress_enabled = false면 null)"
  value       = try(data.aws_lb.ingress[0].dns_name, null)
}

output "aws_lb_name" {
  description = "태그로 찾은 AWS 쪽 ALB 이름. CloudWatch AWS/ApplicationELB 지표의 LoadBalancer 값은 ARN의 app/<이름>/<ID> 부분 (aws_ingress_enabled = false면 null)"
  value       = try(data.aws_lb.ingress[0].name, null)
}

output "aws_lb_arn_suffix" {
  description = "CloudWatch AWS/ApplicationELB 지표의 LoadBalancer 차원 값 (app/<이름>/<ID>)"
  value       = try(data.aws_lb.ingress[0].arn_suffix, null)
}
