# terraform/vpn 루트가 만든 VGW를 이 VPC에 붙이고, app 라우트 테이블에 온프레미스 경로(onprem_cidr -> VGW)를 전파한다.
# VPN 연결(터널 IP, PSK)은 메인 destroy와 상관없이 vpn 루트에 남는다. destroy하면 VGW만 VPC에서 떨어진다.
data "aws_vpn_gateway" "this" {
  tags  = { Name = "${var.project}-vgw" }
  state = "available"
}

resource "aws_vpn_gateway_attachment" "this" {
  vpc_id         = var.vpc_id
  vpn_gateway_id = data.aws_vpn_gateway.this.id
}

# 전파는 VGW가 VPC에 붙은 뒤에만 켤 수 있다. 라우트 테이블마다 따로 켠다
resource "aws_vpn_gateway_route_propagation" "app" {
  count = length(var.route_table_ids)

  vpn_gateway_id = aws_vpn_gateway_attachment.this.vpn_gateway_id
  route_table_id = var.route_table_ids[count.index]
}
