locals {
  name = var.project
}

# SG 본체만 여기서 만들고, 규칙은 아래에서 별도 리소스로 붙인다.
# (ALB SG <-> Node SG가 서로를 참조해서 인라인 규칙을 쓰면 순환 참조가 생김)

resource "aws_security_group" "alb" {
  #checkov:skip=CKV2_AWS_5:ALB는 코드가 아니라 AWS Load Balancer Controller가 만들면서 이 SG를 붙임
  name        = "${local.name}-alb-sg"
  description = "ALB: allow web traffic from the internet"
  vpc_id      = var.vpc_id

  tags = { Name = "${local.name}-alb-sg" }
}

resource "aws_security_group" "node" {
  #checkov:skip=CKV2_AWS_5:eks 모듈의 시작 템플릿에 붙어 있으나 checkov가 모듈 경계를 넘어 추적하지 못함
  name        = "${local.name}-node-sg"
  description = "EKS nodes: allow traffic from ALB and other nodes"
  vpc_id      = var.vpc_id

  tags = { Name = "${local.name}-node-sg" }
}

# DB SG는 두지 않는다. DB(MySQL 8.4)는 온프레미스에서만 운영한다.
# EKS 파드에서 온프레미스 DB로 나가는 연결은 node_all egress가 이미 허용하고, 경로는 온프레미스 연결 방식이 정해지면 추가한다.

# ---------------------------------------------------------------- ALB SG
resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  #checkov:skip=CKV_AWS_260:공개 웹 진입점이라 80 허용이 필요함. 인증서(443) 준비 후 80은 리다이렉트 전용으로 사용
  security_group_id = aws_security_group.alb.id
  description       = "HTTP from internet"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTPS from internet"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

# ALB는 Node의 서비스 포트로만 내보낸다
resource "aws_vpc_security_group_egress_rule" "alb_to_node" {
  security_group_id            = aws_security_group.alb.id
  description                  = "To nodes service ports"
  ip_protocol                  = "tcp"
  from_port                    = var.node_service_port_from
  to_port                      = var.node_service_port_to
  referenced_security_group_id = aws_security_group.node.id
}

# ---------------------------------------------------------------- Node SG
resource "aws_vpc_security_group_ingress_rule" "node_from_alb" {
  security_group_id            = aws_security_group.node.id
  description                  = "Service ports from ALB"
  ip_protocol                  = "tcp"
  from_port                    = var.node_service_port_from
  to_port                      = var.node_service_port_to
  referenced_security_group_id = aws_security_group.alb.id
}

resource "aws_vpc_security_group_ingress_rule" "node_self" {
  security_group_id            = aws_security_group.node.id
  description                  = "All traffic between nodes"
  ip_protocol                  = "-1"
  referenced_security_group_id = aws_security_group.node.id
}

# 온프레미스에서 노드로 들어오는 규칙은 두지 않는다.
# - K8s API는 노드가 아니라 EKS 컨트롤 플레인에 있다 (온프레미스 접근은 vpn 모듈에서 클러스터 SG 443으로 연다)
# - 노드에는 SSH 키가 없다. 노드 접속이 필요하면 SSM Session Manager를 쓴다

# 노드는 NAT를 통해 이미지 pull, 패키지 설치 등 외부 통신이 필요하다
resource "aws_vpc_security_group_egress_rule" "node_all" {
  #checkov:skip=CKV_AWS_382:노드가 NAT를 통해 컨테이너 이미지와 패키지를 받아야 해서 아웃바운드 전체 허용
  security_group_id = aws_security_group.node.id
  description       = "All outbound (via NAT)"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}
