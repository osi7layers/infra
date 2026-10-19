# OCI edge-proxy 공인 IP (고정 IP, edge-proxy 사설 10.0.0.47에 1:1 NAT). 바꾸면 VPN 연결이 다시 만들어진다
customer_gateway_ip = "132.145.89.131"

# 터널 양쪽 대역 (메인의 onprem_cidr, vpc_cidr와 같게)
onprem_cidr  = "10.0.0.0/16"
aws_vpc_cidr = "10.20.0.0/16"
