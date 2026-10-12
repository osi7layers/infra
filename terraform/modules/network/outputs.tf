output "vpc_id" {
  value = aws_vpc.this.id
}

output "vpc_cidr" {
  value = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "app_subnet_ids" {
  value = aws_subnet.app[*].id
}

output "db_subnet_ids" {
  value = aws_subnet.db[*].id
}

# vpn 모듈이 VGW 경로 전파를 설정할 때 사용
output "app_route_table_ids" {
  value = aws_route_table.app[*].id
}

output "db_route_table_id" {
  value = aws_route_table.db.id
}
