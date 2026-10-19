variable "region" {
  description = "AWS 리전 (메인 terraform과 동일)"
  type        = string
  default     = "ap-northeast-2"
}

variable "project" {
  description = "프로젝트 이름 (리소스 이름 접두사, 태그). 메인은 VGW를 Name 태그 <project>-vgw로 찾는다"
  type        = string
  default     = "osi7"
}

variable "customer_gateway_ip" {
  description = "온프레미스 VPN 장비(OCI edge-proxy strongSwan)의 공인 IP. 바꾸면 VPN 연결을 다시 만들어 AWS 터널 IP가 바뀐다"
  type        = string
  default     = "132.145.89.131"

  validation {
    condition     = can(cidrhost("${var.customer_gateway_ip}/32", 0))
    error_message = "IPv4 주소 형식이어야 합니다 (예: 203.0.113.10)."
  }
}

variable "onprem_cidr" {
  description = "VPN 너머 온프레미스 대역 (OCI VCN). 정적 경로와 터널 트래픽 선택자(온프레미스 쪽)에 사용. 메인의 onprem_cidr와 같아야 한다"
  type        = string
  default     = "10.0.0.0/16"
}

variable "aws_vpc_cidr" {
  description = "AWS VPC 대역. 터널 트래픽 선택자(AWS 쪽)에 사용. 메인의 vpc_cidr와 같아야 한다"
  type        = string
  default     = "10.20.0.0/16"
}
