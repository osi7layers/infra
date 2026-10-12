locals {
  name = var.project
}

# SG 본체만 여기서 만들고, 규칙은 아래에서 별도 리소스로 붙인다.
# (ALB SG <-> Node SG가 서로를 참조해서 인라인 규칙을 쓰면 순환 참조가 생김)

resource "aws_security_group" "alb" {
  name        = "${local.name}-alb-sg"
  description = "ALB: allow web traffic from the internet"
  vpc_id      = var.vpc_id

  tags = { Name = "${local.name}-alb-sg" }
}

resource "aws_security_group" "node" {
  name        = "${local.name}-node-sg"
  description = "Kubernetes EC2 nodes: allow traffic from ALB, other nodes and on-prem VPN"
  vpc_id      = var.vpc_id

  tags = { Name = "${local.name}-node-sg" }
}

resource "aws_security_group" "db" {
  name        = "${local.name}-db-sg"
  description = "RDS: allow DB port from nodes and on-prem VPN only"
  vpc_id      = var.vpc_id

  tags = { Name = "${local.name}-db-sg" }
}

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

resource "aws_vpc_security_group_ingress_rule" "node_k8s_api_from_onprem" {
  security_group_id = aws_security_group.node.id
  description       = "Kubernetes API from on-prem over VPN"
  ip_protocol       = "tcp"
  from_port         = 6443
  to_port           = 6443
  cidr_ipv4         = var.onprem_cidr
}

resource "aws_vpc_security_group_ingress_rule" "node_ssh_from_onprem" {
  security_group_id = aws_security_group.node.id
  description       = "SSH from on-prem over VPN"
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
  cidr_ipv4         = var.onprem_cidr
}

# 노드는 NAT를 통해 이미지 pull, 패키지 설치 등 외부 통신이 필요하다
resource "aws_vpc_security_group_egress_rule" "node_all" {
  #checkov:skip=CKV_AWS_382:노드가 NAT를 통해 컨테이너 이미지와 패키지를 받아야 해서 아웃바운드 전체 허용
  security_group_id = aws_security_group.node.id
  description       = "All outbound (via NAT)"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# ---------------------------------------------------------------- DB SG
resource "aws_vpc_security_group_ingress_rule" "db_from_node" {
  security_group_id            = aws_security_group.db.id
  description                  = "DB port from nodes"
  ip_protocol                  = "tcp"
  from_port                    = var.db_port
  to_port                      = var.db_port
  referenced_security_group_id = aws_security_group.node.id
}

resource "aws_vpc_security_group_ingress_rule" "db_from_onprem" {
  security_group_id = aws_security_group.db.id
  description       = "DB port from on-prem over VPN (migration, replication)"
  ip_protocol       = "tcp"
  from_port         = var.db_port
  to_port           = var.db_port
  cidr_ipv4         = var.onprem_cidr
}

# RDS를 온프레미스 MySQL의 복제본으로 둘 경우 RDS가 온프레미스 소스에 접속하므로 온프레미스로만 열어 둔다.
# 복제 방향이 확정되어 필요 없으면 이 규칙을 지운다.
resource "aws_vpc_security_group_egress_rule" "db_to_onprem" {
  security_group_id = aws_security_group.db.id
  description       = "DB port to on-prem over VPN (replication)"
  ip_protocol       = "tcp"
  from_port         = var.db_port
  to_port           = var.db_port
  cidr_ipv4         = var.onprem_cidr
}
