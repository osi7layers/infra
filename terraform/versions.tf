terraform {
  required_version = ">= 1.10.0" # backend의 use_lockfile(S3 잠금)이 1.10부터 지원

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}
