#!/usr/bin/env bash
# 04. IAM 노드 역할: terraform/modules/iam의 노드 역할과 ecr 모듈의 Pull 정책을 CLI로 만든다.
source "$(dirname "$0")/common.sh"
: "${ECR_REPO_ARN:?03-ecr.sh를 먼저 실행하세요}"

step "역할 $PROJECT-node-role (EC2가 맡는 역할)"
aws iam create-role --role-name "$PROJECT-node-role" \
  --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ec2.amazonaws.com"},"Action":"sts:AssumeRole"}]}' \
  --tags Key=Project,Value="$PROJECT" Key=ManagedBy,Value=cli >/dev/null

step "프로젝트 전용 Pull 정책 $PROJECT-ecr-pull"
save ECR_PULL_POLICY_ARN "$(awsq iam create-policy --policy-name "$PROJECT-ecr-pull" --description "ECR image pull only" \
  --policy-document "{\"Version\":\"2012-10-17\",\"Statement\":[
    {\"Sid\":\"GetAuthorizationToken\",\"Effect\":\"Allow\",\"Action\":\"ecr:GetAuthorizationToken\",\"Resource\":\"*\"},
    {\"Sid\":\"PullImages\",\"Effect\":\"Allow\",\"Action\":[\"ecr:BatchCheckLayerAvailability\",\"ecr:BatchGetImage\",\"ecr:GetDownloadUrlForLayer\"],\"Resource\":\"$ECR_REPO_ARN\"}]}" \
  --tags Key=Project,Value="$PROJECT" Key=ManagedBy,Value=cli --query Policy.Arn)"

step "정책 연결 (프로젝트 Pull + EKS 노드 + CNI + AWS 관리형 ECR Pull)"
for arn in "$ECR_PULL_POLICY_ARN" \
  arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy \
  arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy \
  arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPullOnly; do
  aws iam attach-role-policy --role-name "$PROJECT-node-role" --policy-arn "$arn"
  echo "  $arn"
done

step "완료. 다음: ./snapshot.sh cli 로 결과를 기록한 뒤 ./99-cleanup.sh"
