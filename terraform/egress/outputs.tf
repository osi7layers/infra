output "nat_public_ips" {
  description = "AWS NAT 공인 IP. OCI 네트워크 담당에게 edge-proxy 허용 출발지(/32)로 전달한다"
  value       = aws_eip.nat[*].public_ip
}
