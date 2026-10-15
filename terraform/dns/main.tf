# osi7.shop 도메인 전체를 Route 53에 위임한다 (도메인은 가비아에서 구매, 네임서버만 Route 53으로 변경).
# 호스팅 영역은 Terraform이 만들지 않고 콘솔에서 직접 만든다. 영역을 다시 만들면 네임서버 4개가 바뀌어
# 가비아 등록과 위임 대기를 다시 해야 하므로, destroy로 지워질 일이 없게 Terraform 밖에 둔다.
# 여기서는 이미 있는 영역을 이름으로 찾아 레코드와 IAM 권한만 관리한다.
# 인증서 발급용 TXT(_acme-challenge)는 몇 분만 쓰는 값이라 여기서 관리하지 않는다 (수동이면 콘솔, 자동이면 발급 도구가 만들고 지움).

data "aws_route53_zone" "this" {
  name         = var.domain
  private_zone = false
}

# Harbor는 온프레미스 harbor-01에 있고 Tailscale IP로 접속한다 (tailnet 안의 기기에서만 연결됨)
resource "aws_route53_record" "harbor" {
  #checkov:skip=CKV2_AWS_23:AWS 리소스가 아니라 온프레미스 Harbor의 Tailscale IP를 가리키는 레코드
  count = var.harbor_ip == "" ? 0 : 1

  zone_id = data.aws_route53_zone.this.zone_id
  name    = "harbor.${var.domain}"
  type    = "A"
  ttl     = 300
  records = [var.harbor_ip]
}

# ---------------------------------------------------------------- 인증서 자동 갱신용 IAM 사용자
# 온프레미스의 발급 도구(cert-manager 또는 certbot-dns-route53)가 DNS-01 검증 TXT를 직접 만들고 지운다.
# _acme-challenge.<acme_hosts>.<domain> 이름의 TXT만 바꿀 수 있어서, 키가 유출돼도 A 레코드 등은 바꿀 수 없다.
# 액세스 키는 state에 남지 않도록 콘솔에서 발급해 영역 ID와 함께 온프레미스 담당에게 전달한다.
locals {
  acme_record_names = [for h in var.acme_hosts : "_acme-challenge.${h}.${var.domain}"]
}

resource "aws_iam_group" "acme" {
  count = var.create_acme_user ? 1 : 0

  name = "${var.project}-acme-dns"
}

resource "aws_iam_user" "acme" {
  #checkov:skip=CKV_AWS_273:온프레미스 발급 도구는 SSO를 쓸 수 없어 IAM 사용자 사용. 권한은 지정한 TXT 레코드로 제한
  count = var.create_acme_user ? 1 : 0

  name = "${var.project}-acme-harbor"
}

resource "aws_iam_user_group_membership" "acme" {
  count = var.create_acme_user ? 1 : 0

  user   = aws_iam_user.acme[0].name
  groups = [aws_iam_group.acme[0].name]
}

resource "aws_iam_policy" "acme" {
  count = var.create_acme_user ? 1 : 0

  name   = "${var.project}-acme-dns"
  policy = data.aws_iam_policy_document.acme.json
}

resource "aws_iam_group_policy_attachment" "acme" {
  count = var.create_acme_user ? 1 : 0

  group      = aws_iam_group.acme[0].name
  policy_arn = aws_iam_policy.acme[0].arn
}

data "aws_iam_policy_document" "acme" {
  # TXT 반영 여부 확인 (변경 ID는 만들어지기 전에는 알 수 없어 change/* 사용)
  statement {
    sid       = "GetChange"
    actions   = ["route53:GetChange"]
    resources = ["arn:aws:route53:::change/*"]
  }

  # 영역 찾기. 특정 영역에 붙지 않는 조회 작업이라 "*"만 가능
  statement {
    sid       = "FindZone"
    actions   = ["route53:ListHostedZones", "route53:ListHostedZonesByName"]
    resources = ["*"]
  }

  statement {
    sid       = "ReadRecords"
    actions   = ["route53:ListResourceRecordSets"]
    resources = [data.aws_route53_zone.this.arn]
  }

  # 지정한 _acme-challenge 이름의 TXT만 만들고 지울 수 있다
  statement {
    sid       = "ChangeAcmeTxtOnly"
    actions   = ["route53:ChangeResourceRecordSets"]
    resources = [data.aws_route53_zone.this.arn]

    condition {
      test     = "ForAllValues:StringEquals"
      variable = "route53:ChangeResourceRecordSetsNormalizedRecordNames"
      values   = local.acme_record_names
    }

    condition {
      test     = "ForAllValues:StringEquals"
      variable = "route53:ChangeResourceRecordSetsRecordTypes"
      values   = ["TXT"]
    }
  }
}

# ---------------------------------------------------------------- AWS 쪽 HTTPS 인증서 (ACM)
# EKS 앞단 NLB의 TLS 리스너에 붙인다 (Service annotation aws-load-balancer-ssl-cert에 ARN). 인증서 하나에 이름을 모두 넣는다.
# 메인을 destroy해도 남도록 여기 둔다. ACM 공인 인증서는 무료이고, 검증 레코드가 남아 있으면 AWS가 자동으로 갱신한다.
# 온프레미스 쪽 같은 이름의 인증서는 Let's Encrypt(위 acme 사용자)로 따로 발급한다.
resource "aws_acm_certificate" "aws_ingress" {
  domain_name               = "${var.acm_hosts[0]}.${var.domain}"
  subject_alternative_names = [for h in slice(var.acm_hosts, 1, length(var.acm_hosts)) : "${h}.${var.domain}"]
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "acm_validation" {
  for_each = {
    for o in aws_acm_certificate.aws_ingress.domain_validation_options : o.domain_name => o
  }

  zone_id = data.aws_route53_zone.this.zone_id
  name    = each.value.resource_record_name
  type    = each.value.resource_record_type
  ttl     = 300
  records = [each.value.resource_record_value]

  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "aws_ingress" {
  certificate_arn         = aws_acm_certificate.aws_ingress.arn
  validation_record_fqdns = [for r in aws_route53_record.acm_validation : r.fqdn]
}
