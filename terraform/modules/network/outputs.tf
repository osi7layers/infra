output "vpc_id" {
  value = aws_vpc.this.id
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "app_subnet_ids" {
  value = aws_subnet.app[*].id
}

# 온프레미스 연결(VPN 또는 Tailscale)을 만들 때 app 서브넷에서 온프레미스로 가는 경로를 넣는 데 사용
output "app_route_table_ids" {
  value = aws_route_table.app[*].id
}
