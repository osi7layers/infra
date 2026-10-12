# terraform init -backend-config=backend.hcl 로 사용한다.
# 팀 계정으로 옮기면 bucket만 바꾼다 (bootstrap 출력 state_bucket_name 값).
bucket       = "osi7-tfstate-918633123181"
key          = "aws/terraform.tfstate"
region       = "ap-northeast-2"
encrypt      = true
use_lockfile = true # S3 잠금 파일(.tflock)로 동시 apply 방지 (Terraform 1.10+, DynamoDB 불필요)
