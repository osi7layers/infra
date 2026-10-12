output "state_bucket_name" {
  description = "메인 terraform의 backend.hcl에 넣을 bucket 값"
  value       = aws_s3_bucket.state.bucket
}
