#!/usr/bin/env bash
# 메인 destroy 뒤(또는 destroy가 VPC·서브넷·SG에서 실패했을 때) 남은 AWS 리소스를 찾는다.
# Terraform state에 없는데 클러스터가 만든 것들이 남으면 destroy가 DependencyViolation으로 멈추거나 요금이 계속 나간다.
#   - VPC CNI가 노드에 추가로 붙인 ENI(aws-K8S-i-...): 노드가 먼저 종료되면 정리되지 않고 남아 서브넷·노드 SG를 붙잡는다 (2026-10-22 실제 발생)
#   - EKS 클러스터 SG(eks-cluster-sg-<클러스터>-*): 클러스터 삭제 때 위 ENI가 쓰고 있으면 EKS가 지우지 못해 VPC를 붙잡는다
#   - LB Controller가 만든 ALB·대상 그룹, EBS CSI 드라이버가 만든 볼륨 (Ingress·PVC를 먼저 지우지 않았을 때)
#
# 사용법 (terraform 폴더에서, Git Bash):
#   ./scripts/check-leftovers.sh         # 남은 것만 보여 준다 (아무것도 지우지 않음)
#   ./scripts/check-leftovers.sh --fix   # 확인을 받고, 붙어 있지 않은 CNI ENI와 남은 EKS 클러스터 SG만 지운다.
#                                         # 그다음 terraform destroy를 다시 실행한다
#
# 클러스터가 아직 있으면 --fix는 아무것도 지우지 않는다 (ENI·SG가 정상적으로 쓰이는 중이기 때문).
# ALB·EBS는 자동으로 지우지 않는다. 클러스터가 살아 있을 때 Ingress·PVC를 지우는 것이 맞는 순서다 (CLAUDE.md 내리는 순서).
set -euo pipefail
cd "$(dirname "$0")/.."

PROJECT="osi7"
CLUSTER="${PROJECT}-eks"
VPC_NAME="${PROJECT}-vpc"
REGION="${AWS_REGION:-ap-northeast-2}"
FIX=0
[ "${1:-}" = "--fix" ] && FIX=1

aws() { command aws --region "$REGION" --output text "$@" | tr -d '\r'; }
step() { echo; echo "=== $*"; }
FOUND=0
report() { # 제목, 값(비면 없음)
  if [ -n "$2" ] && [ "$2" != "None" ]; then
    echo "남음  $1:"; echo "$2" | sed 's/^/      /'; FOUND=1
  else
    echo "없음  $1"
  fi
}

step "Terraform state (메인)"
STATE_COUNT=$(terraform state list 2>/dev/null | wc -l | tr -d ' ')
echo "state 리소스: $STATE_COUNT"
terraform state list 2>/dev/null | sed 's/^/      /'

step "클러스터와 노드"
CLUSTER_EXISTS=$(aws eks list-clusters --query "clusters[?@=='$CLUSTER'] | [0]")
report "EKS 클러스터 $CLUSTER" "$CLUSTER_EXISTS"
report "EC2 인스턴스 (Project=$PROJECT, 종료 안 됨)" "$(aws ec2 describe-instances \
  --filters Name=tag:Project,Values=$PROJECT Name=instance-state-name,Values=pending,running,stopping,stopped,shutting-down \
  --query 'Reservations[].Instances[].[InstanceId,State.Name]')"

step "Terraform 밖에서 생긴 리소스"
report "ALB/NLB (LB Controller)" "$(aws elbv2 describe-load-balancers \
  --query "LoadBalancers[?contains(LoadBalancerName,'k8s-')].[LoadBalancerName,State.Code]")"
report "EBS 볼륨 (EBS CSI)" "$(aws ec2 describe-volumes \
  --filters Name=tag:ebs.csi.aws.com/cluster,Values=true --query 'Volumes[].[VolumeId,State,Size]')"

VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=$VPC_NAME" --query 'Vpcs[0].VpcId')
step "VPC $VPC_NAME"
if [ -z "$VPC_ID" ] || [ "$VPC_ID" = "None" ]; then
  echo "없음  VPC (정상적으로 지워짐)"
else
  report "VPC" "$VPC_ID"
  report "NAT Gateway" "$(aws ec2 describe-nat-gateways \
    --filter Name=vpc-id,Values=$VPC_ID Name=state,Values=pending,available,deleting --query 'NatGateways[].[NatGatewayId,State]')"
  report "ENI" "$(aws ec2 describe-network-interfaces \
    --filters Name=vpc-id,Values=$VPC_ID --query 'NetworkInterfaces[].[NetworkInterfaceId,Status,Description]')"
  report "보안 그룹 (default 제외)" "$(aws ec2 describe-security-groups \
    --filters Name=vpc-id,Values=$VPC_ID --query "SecurityGroups[?GroupName!='default'].[GroupId,GroupName]")"
  report "서브넷" "$(aws ec2 describe-subnets --filters Name=vpc-id,Values=$VPC_ID --query 'Subnets[].[SubnetId,CidrBlock]')"
fi

if [ "$FIX" = 1 ]; then
  step "--fix: CNI ENI와 EKS 클러스터 SG 정리"
  if [ -n "$CLUSTER_EXISTS" ] && [ "$CLUSTER_EXISTS" != "None" ]; then
    echo "클러스터가 아직 있어서 지우지 않습니다. 먼저 terraform destroy를 실행하세요."
    exit 1
  fi
  # 붙어 있지 않은(available) ENI 중 이 클러스터의 CNI가 만든 것만 고른다
  ENIS=$(aws ec2 describe-network-interfaces \
    --filters Name=status,Values=available Name=tag:cluster.k8s.amazonaws.com/name,Values=$CLUSTER \
    --query 'NetworkInterfaces[].NetworkInterfaceId')
  SGS=$(aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=eks-cluster-sg-${CLUSTER}-*" --query 'SecurityGroups[].GroupId')
  if [ -z "$ENIS" ] && [ -z "$SGS" ]; then
    echo "지울 것이 없습니다."
    exit 0
  fi
  echo "지울 ENI: ${ENIS:-없음}"
  echo "지울 SG:  ${SGS:-없음}"
  read -r -p "지울까요? (yes 입력) " answer
  [ "$answer" = "yes" ] || { echo "취소했습니다."; exit 1; }
  for eni in $ENIS; do aws ec2 delete-network-interface --network-interface-id "$eni" && echo "삭제 ENI $eni"; done
  for sg in $SGS; do aws ec2 delete-security-group --group-id "$sg" >/dev/null && echo "삭제 SG $sg"; done
  echo
  echo "다음: terraform destroy를 다시 실행해 남은 VPC·서브넷·SG를 지운 뒤, 이 스크립트를 다시 돌려 모두 '없음'인지 확인합니다."
  exit 0
fi

echo
if [ "$FOUND" = 0 ] && [ "$STATE_COUNT" = 0 ]; then
  echo "정리 완료: 메인 state가 비었고 남은 리소스가 없습니다. (egress EIP, ECR, iam-users, dns는 원래 남아 있음)"
else
  echo "남은 것이 있습니다."
  echo "  - CNI ENI(aws-K8S-i-...)나 eks-cluster-sg-${CLUSTER}-* 가 VPC를 붙잡고 있으면: ./scripts/check-leftovers.sh --fix -> terraform destroy"
  echo "  - ALB·EBS가 남았으면: 클러스터가 있을 때 Ingress·PVC를 먼저 지운다 (이미 클러스터가 없으면 콘솔에서 확인 후 삭제)"
fi
