# AWS NAT Gateway용 고정 공인 IP (EIP).
# EKS의 앱은 NAT로 인터넷에 나가 OCI edge-proxy(132.145.89.131)의 TCP 프록시로 온프레미스 DB에 접속하고,
# OCI 보안 목록은 이 IP만 허용한다. NAT의 EIP를 메인에서 만들면 apply할 때마다 IP가 바뀌므로, 메인과 따로 두고
# 프로젝트가 끝날 때까지 지우지 않는다. 메인 network 모듈이 이름 태그로 찾아 NAT에 붙인다.
# 공인 IPv4는 붙어 있든 아니든 시간당 $0.005 (월 약 $3.6)가 나간다.

resource "aws_eip" "nat" {
  #checkov:skip=CKV2_AWS_19:EC2가 아니라 메인의 NAT Gateway에 붙이는 EIP (메인을 내린 동안에는 붙지 않은 상태로 IP만 유지)
  count  = var.nat_eip_count
  domain = "vpc"

  tags = { Name = "${var.project}-egress-eip-${count.index}" }

  # 다시 만들면 IP가 바뀌어 OCI 보안 목록을 다시 바꿔야 한다
  lifecycle {
    prevent_destroy = true
  }
}
