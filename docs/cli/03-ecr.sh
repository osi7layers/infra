#!/usr/bin/env bash
# 03. ECR: terraform/modules/ecr와 같은 설정으로 리포지토리 1개를 만든다.
source "$(dirname "$0")/common.sh"

step "리포지토리 $ECR_REPO (IMMUTABLE, push 시 스캔, KMS 암호화)"
save ECR_REPO_ARN "$(awsq ecr create-repository --repository-name "$ECR_REPO" \
  --image-tag-mutability IMMUTABLE \
  --image-scanning-configuration scanOnPush=true \
  --encryption-configuration encryptionType=KMS \
  --tags Key=Project,Value="$PROJECT" Key=ManagedBy,Value=cli \
  --query repository.repositoryArn)"

step "수명 주기 정책: 최근 ${ECR_KEEP}개만 보관"
# description은 Windows aws cli의 한글 인코딩 문제를 피하려고 영어로 쓴다 (Terraform은 "최근 10개만 보관")
aws ecr put-lifecycle-policy --repository-name "$ECR_REPO" --lifecycle-policy-text \
  "{\"rules\":[{\"rulePriority\":1,\"description\":\"keep latest $ECR_KEEP images\",\"selection\":{\"tagStatus\":\"any\",\"countType\":\"imageCountMoreThan\",\"countNumber\":$ECR_KEEP},\"action\":{\"type\":\"expire\"}}]}" >/dev/null

step "완료. 다음: ./04-iam.sh"
