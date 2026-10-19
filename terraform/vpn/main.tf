# [폐기 예정] 온프레미스 연결을 VPN 대신 NAT(고정 EIP, terraform/egress) + OCI edge-proxy TCP 프록시로 바꿔서
# 이 루트는 destroy한 뒤 폴더째 지운다. destroy할 수 있게 prevent_destroy를 뺐다.
#
# 온프레미스(OCI)와의 Site-to-Site VPN (AWS VGW <-> OCI edge-proxy의 strongSwan, IPsec).
# EKS의 앱이 OCI DB에 이 경로로 접속한다. OCI 쪽 경로는 private 라우트 테이블의 10.20.0.0/16 -> edge-proxy.
#
# AWS 쪽 터널 외부 IP는 직접 정할 수 없고 VPN 연결이 살아 있는 동안만 유지된다. 그래서 메인과 따로 두고
# 프로젝트가 끝날 때까지 지우지 않으려 했다 (OCI 보안 목록과 strongSwan 설정을 한 번만 하려고). VPN 연결은 켜 둔
# 시간만큼 과금된다 (시간당 약 $0.05). VGW는 여기서 만들고, VPC에 붙이는 것은 메인(vpn-attachment 모듈)이 한다.

resource "aws_vpn_gateway" "this" {
  tags = { Name = "${var.project}-vgw" }

}

resource "aws_customer_gateway" "onprem" {
  bgp_asn    = 65000 # 정적 라우팅이라 쓰이지 않지만 필수 값 (사설 ASN)
  ip_address = var.customer_gateway_ip
  type       = "ipsec.1"

  tags = { Name = "${var.project}-cgw-oci-edge-proxy" }

}

resource "aws_vpn_connection" "onprem" {
  vpn_gateway_id      = aws_vpn_gateway.this.id
  customer_gateway_id = aws_customer_gateway.onprem.id
  type                = "ipsec.1"
  static_routes_only  = true # strongSwan만 쓰므로 BGP 없이 정적 경로

  # 터널에 태울 트래픽 (온프레미스 쪽 / AWS 쪽). strongSwan의 leftsubnet / rightsubnet과 맞춘다
  local_ipv4_network_cidr  = var.onprem_cidr
  remote_ipv4_network_cidr = var.aws_vpc_cidr

  # PSK는 AWS가 생성한다 (state에 남고, 출력 tunnel_preshared_keys로 확인). edge-proxy는 1:1 NAT 뒤라 NAT-T(UDP 4500)로 맺는다
  tunnel1_ike_versions = ["ikev2"]
  tunnel2_ike_versions = ["ikev2"]

  tags = { Name = "${var.project}-vpn-oci" }

}

resource "aws_vpn_connection_route" "onprem" {
  vpn_connection_id      = aws_vpn_connection.onprem.id
  destination_cidr_block = var.onprem_cidr
}
