locals {
  name = var.project
}

# ---------------------------------------------------------------- VPC
resource "aws_vpc" "this" {
  #checkov:skip=CKV2_AWS_11:학습용 4주 프로젝트라 Flow Logs 저장 비용을 쓰지 않음. 운영 환경이면 활성화할 것
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${local.name}-vpc" }
}

# 기본 SG는 규칙을 모두 비워 사용하지 못하게 한다. 실제 SG는 security 모듈에서 만든다.
resource "aws_default_security_group" "this" {
  vpc_id = aws_vpc.this.id

  tags = { Name = "${local.name}-default-sg-unused" }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = { Name = "${local.name}-igw" }
}

# ---------------------------------------------------------------- 서브넷
resource "aws_subnet" "public" {
  count = length(var.azs)

  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.azs[count.index]
  map_public_ip_on_launch = false

  tags = { Name = "${local.name}-public-${substr(var.azs[count.index], -1, 1)}", Tier = "public", "kubernetes.io/role/elb" = "1" }
}

resource "aws_subnet" "app" {
  count = length(var.azs)

  vpc_id            = aws_vpc.this.id
  cidr_block        = var.app_subnet_cidrs[count.index]
  availability_zone = var.azs[count.index]

  tags = { Name = "${local.name}-app-${substr(var.azs[count.index], -1, 1)}", Tier = "app", "kubernetes.io/role/internal-elb" = "1" }
}

# DB 서브넷은 두지 않는다. DB(MySQL 8.4)는 온프레미스에서만 운영하고, AWS에는 RDS도 백업 복제도 없다.

# ---------------------------------------------------------------- NAT Gateway
resource "aws_eip" "nat" {
  count  = var.nat_gateway_count
  domain = "vpc"

  tags = { Name = "${local.name}-nat-eip-${count.index}" }

  depends_on = [aws_internet_gateway.this]
}

resource "aws_nat_gateway" "this" {
  count = var.nat_gateway_count

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = { Name = "${local.name}-nat-${count.index}" }

  depends_on = [aws_internet_gateway.this]
}

# ---------------------------------------------------------------- 라우팅: Public
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  tags = { Name = "${local.name}-rt-public" }
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  count = length(var.azs)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# ---------------------------------------------------------------- 라우팅: Private App
# AZ별로 라우트 테이블을 두고, NAT가 1개면 모두 같은 NAT를 사용한다.
resource "aws_route_table" "app" {
  count  = length(var.azs)
  vpc_id = aws_vpc.this.id

  tags = { Name = "${local.name}-rt-app-${substr(var.azs[count.index], -1, 1)}" }
}

resource "aws_route" "app_nat" {
  count = length(var.azs)

  route_table_id         = aws_route_table.app[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[min(count.index, var.nat_gateway_count - 1)].id
}

resource "aws_route_table_association" "app" {
  count = length(var.azs)

  subnet_id      = aws_subnet.app[count.index].id
  route_table_id = aws_route_table.app[count.index].id
}
