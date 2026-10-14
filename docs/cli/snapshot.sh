#!/usr/bin/env bash
# 지금 AWS에 있는 osi7 네트워크·SG·ECR·IAM 구성을 ID 없이 텍스트로 뽑는다.
# CLI로 만든 직후와 Terraform으로 만든 직후에 각각 실행해서 diff로 비교한다 (QA A-IAC-01 3단계).
#   ./snapshot.sh cli        -> snapshot-cli.txt
#   ./snapshot.sh terraform  -> snapshot-terraform.txt
#   diff snapshot-cli.txt snapshot-terraform.txt
# ID, 생성 시각, ManagedBy 태그처럼 만들 때마다 달라지는 값은 넣지 않는다.
source "$(dirname "$0")/common.sh"
label=${1:?사용법: ./snapshot.sh cli 또는 ./snapshot.sh terraform}
out="$(dirname "$0")/snapshot-$label.txt"

vpc=$(awsq ec2 describe-vpcs --filters Name=tag:Name,Values="$PROJECT-vpc" --query 'Vpcs[0].VpcId')
[ "$vpc" = "None" ] && { echo "$PROJECT-vpc가 없습니다"; exit 1; }
[ "$(awsq ec2 describe-vpcs --filters Name=tag:Name,Values="$PROJECT-vpc" --query 'length(Vpcs)')" = "1" ] \
  || { echo "$PROJECT-vpc가 두 개 이상입니다. CLI로 만든 것을 먼저 정리하세요"; exit 1; }

# SG ID -> 이름 (규칙이 다른 SG를 참조할 때 ID 대신 이름으로 보이게)
declare -A sgname
while read -r id name; do sgname[$id]=$name; done < <(awsq ec2 describe-security-groups \
  --filters Name=vpc-id,Values="$vpc" --query 'SecurityGroups[].[GroupId,GroupName]')
# 서브넷·NAT·IGW ID -> 이름
name_of() { awsq ec2 describe-tags --filters Name=resource-id,Values="$1" Name=key,Values=Name --query 'Tags[0].Value'; }

{
  echo "## VPC"
  awsq ec2 describe-vpcs --vpc-ids "$vpc" --query 'Vpcs[0].[CidrBlock]'
  echo "dns-support=$(awsq ec2 describe-vpc-attribute --vpc-id "$vpc" --attribute enableDnsSupport --query EnableDnsSupport.Value)"
  echo "dns-hostnames=$(awsq ec2 describe-vpc-attribute --vpc-id "$vpc" --attribute enableDnsHostnames --query EnableDnsHostnames.Value)"

  echo; echo "## 서브넷 (이름 CIDR AZ 공인IP자동 Tier elb internal-elb)"
  awsq ec2 describe-subnets --filters Name=vpc-id,Values="$vpc" --query 'Subnets[].[
      Tags[?Key==`Name`]|[0].Value, CidrBlock, AvailabilityZone, MapPublicIpOnLaunch,
      Tags[?Key==`Tier`]|[0].Value, Tags[?Key==`kubernetes.io/role/elb`]|[0].Value,
      Tags[?Key==`kubernetes.io/role/internal-elb`]|[0].Value]' | sort

  echo; echo "## 라우트 테이블 (이름: 목적지 -> 대상 / 연결된 서브넷)"
  while read -r rt; do
    n=$(name_of "$rt"); [ "$n" = "None" ] && n="(기본 라우트 테이블)"
    routes=$(awsq ec2 describe-route-tables --route-table-ids "$rt" \
      --query 'RouteTables[0].Routes[].[DestinationCidrBlock, GatewayId || NatGatewayId]' |
      while read -r dst tgt; do
        case $tgt in local) t=local ;; *) t=$(name_of "$tgt") ;; esac
        echo -n "$dst->$t "
      done)
    subs=$(for s in $(awsq ec2 describe-route-tables --route-table-ids "$rt" \
      --query 'RouteTables[0].Associations[?SubnetId].SubnetId'); do name_of "$s"; done | sort | tr '\n' ' ')
    echo "$n: $routes/ $subs"
  done < <(awsq ec2 describe-route-tables --filters Name=vpc-id,Values="$vpc" --query 'RouteTables[].RouteTableId' | tr '\t' '\n') | sort

  echo; echo "## NAT (이름 서브넷)"
  awsq ec2 describe-nat-gateways --filter Name=vpc-id,Values="$vpc" Name=state,Values=available \
    --query 'NatGateways[].[Tags[?Key==`Name`]|[0].Value, SubnetId]' |
    while read -r n s; do echo "$n $(name_of "$s")"; done | sort

  echo; echo "## SG 규칙 (SG 방향 프로토콜 포트 대상 설명)"
  awsq ec2 describe-security-group-rules --filters Name=group-id,Values="$(IFS=,; echo "${!sgname[*]}")" \
    --query 'SecurityGroupRules[].[GroupId, IsEgress, IpProtocol, FromPort, ToPort, CidrIpv4 || ReferencedGroupInfo.GroupId, Description]' |
    while IFS=$'\t' read -r g e p f t tgt d; do
      [ -n "${sgname[$tgt]:-}" ] && tgt=${sgname[$tgt]}
      dir=ingress; [ "$e" = "True" ] && dir=egress
      echo "${sgname[$g]} $dir $p $f-$t $tgt \"$d\""
    done | sort
  echo; echo "## SG 설명"
  awsq ec2 describe-security-groups --filters Name=vpc-id,Values="$vpc" --query 'SecurityGroups[].[GroupName, Description]' | sort

  echo; echo "## ECR $ECR_REPO (태그규칙 스캔 암호화 / 보관 개수)"
  awsq ecr describe-repositories --repository-names "$ECR_REPO" --query 'repositories[0].[
      imageTagMutability, imageScanningConfiguration.scanOnPush, encryptionConfiguration.encryptionType]' 2>/dev/null || echo "(없음)"
  aws ecr get-lifecycle-policy --repository-name "$ECR_REPO" --query lifecyclePolicyText --output text 2>/dev/null |
    tr -d '\r' | grep -o '"countNumber":[0-9]*' || echo "(정책 없음)"

  echo; echo "## IAM $PROJECT-node-role 연결 정책"
  awsq iam list-attached-role-policies --role-name "$PROJECT-node-role" --query 'AttachedPolicies[].PolicyName' 2>/dev/null |
    tr '\t' '\n' | sort || echo "(없음)"
} >"$out"

echo "저장: $out"
cat "$out"
