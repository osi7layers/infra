#!/usr/bin/env bash
# 99. 정리: 01~04에서 만든 것을 만든 순서의 반대로 지운다.
# 이미 지워졌거나 없는 리소스는 건너뛴다. 끝나면 ManagedBy=cli 태그로 남은 것이 없는지 확인한다.
source "$(dirname "$0")/common.sh"
set +e # 하나가 실패해도 나머지 정리는 계속한다

try() { "$@" >/dev/null 2>&1 && echo "  삭제: ${*: -1}" || echo "  건너뜀(없음 또는 실패): ${*: -1}"; }

step "IAM: 역할에서 정책 떼기 -> 정책, 역할 삭제"
for arn in "${ECR_PULL_POLICY_ARN:-}" \
  arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy \
  arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy \
  arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPullOnly; do
  [ -n "$arn" ] && try aws iam detach-role-policy --role-name "$PROJECT-node-role" --policy-arn "$arn"
done
[ -n "${ECR_PULL_POLICY_ARN:-}" ] && try aws iam delete-policy --policy-arn "$ECR_PULL_POLICY_ARN"
try aws iam delete-role --role-name "$PROJECT-node-role"

step "ECR 리포지토리 (이미지가 있어도 삭제)"
try aws ecr delete-repository --repository-name "$ECR_REPO" --force

step "SG: 서로 참조하는 규칙을 먼저 지워야 SG를 지울 수 있다"
if [ -n "${ALB_SG_ID:-}" ] && [ -n "${NODE_SG_ID:-}" ]; then
  for rule in $(awsq ec2 describe-security-group-rules --filters Name=group-id,Values="$ALB_SG_ID","$NODE_SG_ID" \
    --query 'SecurityGroupRules[?ReferencedGroupInfo.GroupId!=`null`].[GroupId,SecurityGroupRuleId,IsEgress]' | tr '\t' ','); do
    IFS=, read -r g r e <<<"$rule"
    if [ "$e" = "True" ]; then try aws ec2 revoke-security-group-egress --group-id "$g" --security-group-rule-ids "$r"
    else try aws ec2 revoke-security-group-ingress --group-id "$g" --security-group-rule-ids "$r"; fi
  done
fi
for sg in "${ALB_SG_ID:-}" "${NODE_SG_ID:-}"; do [ -n "$sg" ] && try aws ec2 delete-security-group --group-id "$sg"; done

step "NAT 게이트웨이 -> 삭제 완료까지 대기 (1~3분) -> EIP 반납"
if [ -n "${NAT_ID:-}" ]; then
  try aws ec2 delete-nat-gateway --nat-gateway-id "$NAT_ID"
  aws ec2 wait nat-gateway-deleted --nat-gateway-ids "$NAT_ID" 2>/dev/null
fi
[ -n "${EIP_ALLOC_ID:-}" ] && try aws ec2 release-address --allocation-id "$EIP_ALLOC_ID"

step "라우트 테이블 (서브넷 연결을 먼저 끊음)"
for rt in "${PUBLIC_RT_ID:-}" "${APP_RT_0:-}" "${APP_RT_1:-}"; do
  [ -z "$rt" ] && continue
  for assoc in $(awsq ec2 describe-route-tables --route-table-ids "$rt" \
    --query 'RouteTables[0].Associations[?!Main].RouteTableAssociationId' 2>/dev/null); do
    try aws ec2 disassociate-route-table --association-id "$assoc"
  done
  try aws ec2 delete-route-table --route-table-id "$rt"
done

step "서브넷"
for sn in "${PUBLIC_SUBNET_0:-}" "${PUBLIC_SUBNET_1:-}" "${APP_SUBNET_0:-}" "${APP_SUBNET_1:-}"; do
  [ -n "$sn" ] && try aws ec2 delete-subnet --subnet-id "$sn"
done

step "인터넷 게이트웨이 -> VPC (기본 SG와 기본 라우트 테이블은 VPC와 함께 지워짐)"
if [ -n "${IGW_ID:-}" ]; then
  try aws ec2 detach-internet-gateway --internet-gateway-id "$IGW_ID" --vpc-id "${VPC_ID:-}"
  try aws ec2 delete-internet-gateway --internet-gateway-id "$IGW_ID"
fi
[ -n "${VPC_ID:-}" ] && try aws ec2 delete-vpc --vpc-id "$VPC_ID"

step "남은 리소스 확인 (ManagedBy=cli 태그, 비어 있어야 함)"
# 삭제한 NAT는 태그 검색에 한동안 남으므로 NAT는 빼고, 상태로 따로 확인한다
left=$(awsq resourcegroupstaggingapi get-resources --tag-filters Key=ManagedBy,Values=cli \
  --query 'ResourceTagMappingList[].ResourceARN' | tr '\t' '\n' | sed '/^$/d' | grep -v ':natgateway/')
left_nat=$(awsq ec2 describe-nat-gateways --filter Name=tag:ManagedBy,Values=cli \
  --query 'NatGateways[?State!=`deleted`].NatGatewayId')
left="$left$left_nat"
left_iam=$(awsq iam list-roles --query "Roles[?RoleName=='$PROJECT-node-role'].RoleName")
if [ -z "$left" ] && [ -z "$left_iam" ]; then
  echo "  남은 것 없음"
  : >"$STATE_FILE"
else
  echo "  아직 남음 (삭제가 반영되는 데 몇 분 걸릴 수 있음. 잠시 뒤 다시 실행):"
  echo "$left" "$left_iam"
fi
