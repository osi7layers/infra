# 모든 Terraform 루트(메인, iam-users, dns)의 state를 저장할 S3 버킷.
# 이 폴더의 state는 로컬에 둔다 (버킷이 생기기 전이라 원격에 둘 수 없음). 계정마다 한 번만 apply 한다.

data "aws_caller_identity" "current" {}

locals {
  # S3 버킷 이름은 전 세계에서 고유해야 해서 계정 ID를 붙인다. 팀 계정에서 실행하면 이름이 자동으로 바뀐다.
  bucket_name = "${var.project}-tfstate-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket" "state" {
  #checkov:skip=CKV_AWS_18:state 버킷 접근 로그는 로그 버킷 비용 대비 효과가 낮아 생략 (학습 프로젝트)
  #checkov:skip=CKV_AWS_144:교차 리전 복제는 비용 때문에 생략. 버전 관리로 복구 가능
  #checkov:skip=CKV2_AWS_62:state 변경 이벤트 알림은 필요 없음
  #checkov:skip=CKV_AWS_145:SSE-S3(AES256)로 암호화. KMS 키 비용을 쓰지 않음
  bucket = local.bucket_name

  # 실수로 destroy 해도 버킷(=모든 state)이 지워지지 않게 한다
  lifecycle {
    prevent_destroy = true
  }
}

# state가 잘못 덮어써져도 이전 버전으로 되돌릴 수 있게 한다
resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket = aws_s3_bucket.state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# 이전 버전이 끝없이 쌓이지 않게 정리한다. 잠금 파일(.tflock)의 이전 버전도 함께 정리된다.
resource "aws_s3_bucket_lifecycle_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    id     = "expire-noncurrent-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_version_days
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  depends_on = [aws_s3_bucket_versioning.state]
}

# HTTPS가 아닌 요청은 모두 거부한다
data "aws_iam_policy_document" "state" {
  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.state.arn,
      "${aws_s3_bucket.state.arn}/*",
    ]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "state" {
  bucket = aws_s3_bucket.state.id
  policy = data.aws_iam_policy_document.state.json

  # 퍼블릭 차단이 먼저 적용된 뒤에 정책을 붙인다
  depends_on = [aws_s3_bucket_public_access_block.state]
}
