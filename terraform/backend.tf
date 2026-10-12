# state는 S3에 저장한다. backend 블록에는 변수를 쓸 수 없어서, 계정마다 다른 값은 backend.hcl에 둔다.
#   terraform init -backend-config=backend.hcl
# 버킷은 bootstrap/ 폴더에서 먼저 만든다.
terraform {
  backend "s3" {}
}
