output "vpn_gateway_id" {
  description = "VGW ID. 메인의 vpn-attachment 모듈이 Name 태그로 찾아 VPC에 붙인다"
  value       = aws_vpn_gateway.this.id
}

output "vpn_connection_id" {
  description = "strongSwan 설정 파일은 aws ec2 get-vpn-connection-device-sample-configuration --vpn-connection-id <이 값>으로 받는다"
  value       = aws_vpn_connection.onprem.id
}

output "tunnel_addresses" {
  description = "AWS 쪽 터널 외부 IP 2개. strongSwan의 상대(right) 주소이자 OCI public 보안 목록 UDP 500/4500 허용 대상"
  value       = [aws_vpn_connection.onprem.tunnel1_address, aws_vpn_connection.onprem.tunnel2_address]
}

output "tunnel_inside_cidrs" {
  description = "터널 안쪽 /30 대역 2개 (route-based VTI로 설정할 때 사용)"
  value       = [aws_vpn_connection.onprem.tunnel1_inside_cidr, aws_vpn_connection.onprem.tunnel2_inside_cidr]
}

output "tunnel_preshared_keys" {
  description = "터널 PSK 2개. terraform output -json tunnel_preshared_keys로 보고 네트워크 담당에게 DM으로만 전달"
  value       = [aws_vpn_connection.onprem.tunnel1_preshared_key, aws_vpn_connection.onprem.tunnel2_preshared_key]
  sensitive   = true
}
