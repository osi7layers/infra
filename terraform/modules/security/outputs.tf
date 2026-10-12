output "alb_sg_id" {
  value = aws_security_group.alb.id
}

output "node_sg_id" {
  value = aws_security_group.node.id
}

output "db_sg_id" {
  value = aws_security_group.db.id
}
