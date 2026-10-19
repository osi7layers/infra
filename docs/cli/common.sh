#!/usr/bin/env bash
# CLI 단계 스크립트가 함께 쓰는 값과 함수.
# 값은 terraform/terraform.tfvars와 같게 맞춘다 (나중에 Terraform 결과와 비교하기 위해).
set -euo pipefail

export AWS_PAGER=""
export AWS_REGION="ap-northeast-2"

PROJECT="osi7"
VPC_CIDR="10.20.0.0/16"
AZS=("ap-northeast-2a" "ap-northeast-2c")
PUBLIC_CIDRS=("10.20.0.0/24" "10.20.1.0/24")
APP_CIDRS=("10.20.10.0/24" "10.20.11.0/24")
NODE_PORT_FROM=9080 # APISIX gateway (ALB target-type ip)
NODE_PORT_TO=9080
ECR_REPO="ecommerce/web"
ECR_KEEP=10

# 만든 리소스 ID를 다음 스크립트와 정리 스크립트에 넘기는 파일 (git에 올리지 않음)
STATE_FILE="$(dirname "${BASH_SOURCE[0]}")/.state.env"
touch "$STATE_FILE"
# shellcheck disable=SC1090
source "$STATE_FILE"

# aws 결과에서 Windows 줄바꿈(\r)을 지운다
awsq() { aws "$@" --output text | tr -d '\r'; }

save() { # save 이름 값
  sed -i "/^$1=/d" "$STATE_FILE"
  echo "$1=$2" >>"$STATE_FILE"
  printf -v "$1" '%s' "$2"
  echo "  $1=$2"
}

# --tag-specifications 값. ManagedBy=cli로 Terraform이 만든 것(ManagedBy=terraform)과 구분한다
tagspec() { # tagspec 리소스타입 이름 [추가 태그 "{Key=..,Value=..}" ...]
  local type=$1 name=$2; shift 2
  local extra=""
  for t in "$@"; do extra+=",$t"; done
  echo "ResourceType=$type,Tags=[{Key=Name,Value=$name},{Key=Project,Value=$PROJECT},{Key=ManagedBy,Value=cli}$extra]"
}

az_suffix() { echo "${1: -1}"; } # ap-northeast-2a -> a (Terraform의 substr(az, -1, 1))

step() { echo; echo "=== $*"; }
