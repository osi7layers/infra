#!/usr/bin/env bash
# 01. 네트워크: terraform/modules/network와 같은 구성을 CLI로 만든다.
# VPC -> 기본 SG 비우기 -> IGW -> 서브넷 4개 -> EIP, NAT -> 라우트 테이블
# NAT는 시간당 요금이 나가므로 확인이 끝나면 바로 99-cleanup.sh를 실행한다.
source "$(dirname "$0")/common.sh"

step "VPC"
save VPC_ID "$(awsq ec2 create-vpc --cidr-block "$VPC_CIDR" \
  --tag-specifications "$(tagspec vpc "$PROJECT-vpc")" --query Vpc.VpcId)"
aws ec2 modify-vpc-attribute --vpc-id "$VPC_ID" --enable-dns-support '{"Value":true}'
aws ec2 modify-vpc-attribute --vpc-id "$VPC_ID" --enable-dns-hostnames '{"Value":true}'

step "기본 SG 규칙 비우기 (Terraform의 aws_default_security_group과 같음)"
save DEFAULT_SG_ID "$(awsq ec2 describe-security-groups \
  --filters Name=vpc-id,Values="$VPC_ID" Name=group-name,Values=default --query 'SecurityGroups[0].GroupId')"
aws ec2 revoke-security-group-ingress --group-id "$DEFAULT_SG_ID" \
  --ip-permissions "[{\"IpProtocol\":\"-1\",\"UserIdGroupPairs\":[{\"GroupId\":\"$DEFAULT_SG_ID\"}]}]" >/dev/null
aws ec2 revoke-security-group-egress --group-id "$DEFAULT_SG_ID" \
  --ip-permissions '[{"IpProtocol":"-1","IpRanges":[{"CidrIp":"0.0.0.0/0"}]}]' >/dev/null
aws ec2 create-tags --resources "$DEFAULT_SG_ID" \
  --tags Key=Name,Value="$PROJECT-default-sg-unused" Key=Project,Value="$PROJECT" Key=ManagedBy,Value=cli

step "인터넷 게이트웨이"
save IGW_ID "$(awsq ec2 create-internet-gateway \
  --tag-specifications "$(tagspec internet-gateway "$PROJECT-igw")" --query InternetGateway.InternetGatewayId)"
aws ec2 attach-internet-gateway --internet-gateway-id "$IGW_ID" --vpc-id "$VPC_ID"

step "서브넷 (public, app × AZ 2개)"
for i in 0 1; do
  az=${AZS[$i]}; s=$(az_suffix "$az")
  save "PUBLIC_SUBNET_$i" "$(awsq ec2 create-subnet --vpc-id "$VPC_ID" --cidr-block "${PUBLIC_CIDRS[$i]}" --availability-zone "$az" \
    --tag-specifications "$(tagspec subnet "$PROJECT-public-$s" '{Key=Tier,Value=public}' '{Key=kubernetes.io/role/elb,Value=1}')" \
    --query Subnet.SubnetId)"
  save "APP_SUBNET_$i" "$(awsq ec2 create-subnet --vpc-id "$VPC_ID" --cidr-block "${APP_CIDRS[$i]}" --availability-zone "$az" \
    --tag-specifications "$(tagspec subnet "$PROJECT-app-$s" '{Key=Tier,Value=app}' '{Key=kubernetes.io/role/internal-elb,Value=1}')" \
    --query Subnet.SubnetId)"
done

step "NAT 게이트웨이 1개 (public-a에 둠, 두 AZ가 함께 사용)"
save EIP_ALLOC_ID "$(awsq ec2 allocate-address --domain vpc \
  --tag-specifications "$(tagspec elastic-ip "$PROJECT-nat-eip-0")" --query AllocationId)"
save NAT_ID "$(awsq ec2 create-nat-gateway --subnet-id "$PUBLIC_SUBNET_0" --allocation-id "$EIP_ALLOC_ID" \
  --tag-specifications "$(tagspec natgateway "$PROJECT-nat-0")" --query NatGateway.NatGatewayId)"
echo "  NAT가 available이 될 때까지 기다림 (1~3분)"
aws ec2 wait nat-gateway-available --nat-gateway-ids "$NAT_ID"

step "라우트 테이블: public (인터넷 -> IGW)"
save PUBLIC_RT_ID "$(awsq ec2 create-route-table --vpc-id "$VPC_ID" \
  --tag-specifications "$(tagspec route-table "$PROJECT-rt-public")" --query RouteTable.RouteTableId)"
aws ec2 create-route --route-table-id "$PUBLIC_RT_ID" --destination-cidr-block 0.0.0.0/0 --gateway-id "$IGW_ID" >/dev/null
for i in 0 1; do
  v="PUBLIC_SUBNET_$i"
  aws ec2 associate-route-table --route-table-id "$PUBLIC_RT_ID" --subnet-id "${!v}" >/dev/null
done

step "라우트 테이블: app (AZ별, 인터넷 -> NAT)"
for i in 0 1; do
  s=$(az_suffix "${AZS[$i]}")
  save "APP_RT_$i" "$(awsq ec2 create-route-table --vpc-id "$VPC_ID" \
    --tag-specifications "$(tagspec route-table "$PROJECT-rt-app-$s")" --query RouteTable.RouteTableId)"
  rt="APP_RT_$i"; sn="APP_SUBNET_$i"
  aws ec2 create-route --route-table-id "${!rt}" --destination-cidr-block 0.0.0.0/0 --nat-gateway-id "$NAT_ID" >/dev/null
  aws ec2 associate-route-table --route-table-id "${!rt}" --subnet-id "${!sn}" >/dev/null
done

step "완료. 다음: ./02-security.sh"
