#!/usr/bin/env bash
# 02. 보안 그룹: terraform/modules/security와 같은 구성을 CLI로 만든다.
# ALB SG와 노드 SG는 서로를 참조하므로 SG 두 개를 먼저 만들고 규칙을 나중에 붙인다.
source "$(dirname "$0")/common.sh"
: "${VPC_ID:?01-network.sh를 먼저 실행하세요}"

step "SG 본체"
save ALB_SG_ID "$(awsq ec2 create-security-group --vpc-id "$VPC_ID" --group-name "$PROJECT-alb-sg" \
  --description "ALB: allow web traffic from the internet" \
  --tag-specifications "$(tagspec security-group "$PROJECT-alb-sg")" --query GroupId)"
save NODE_SG_ID "$(awsq ec2 create-security-group --vpc-id "$VPC_ID" --group-name "$PROJECT-node-sg" \
  --description "EKS nodes: allow traffic from ALB and other nodes" \
  --tag-specifications "$(tagspec security-group "$PROJECT-node-sg")" --query GroupId)"

step "새 SG에 자동으로 생기는 '아웃바운드 전체 허용'을 지움 (Terraform도 이 규칙을 지우고 필요한 것만 붙인다)"
for sg in "$ALB_SG_ID" "$NODE_SG_ID"; do
  aws ec2 revoke-security-group-egress --group-id "$sg" \
    --ip-permissions '[{"IpProtocol":"-1","IpRanges":[{"CidrIp":"0.0.0.0/0"}]}]' >/dev/null
done

step "ALB SG 규칙: 인터넷 80/443 허용, 노드 서비스 포트로만 내보냄"
aws ec2 authorize-security-group-ingress --group-id "$ALB_SG_ID" --ip-permissions \
  '[{"IpProtocol":"tcp","FromPort":80,"ToPort":80,"IpRanges":[{"CidrIp":"0.0.0.0/0","Description":"HTTP from internet"}]},
    {"IpProtocol":"tcp","FromPort":443,"ToPort":443,"IpRanges":[{"CidrIp":"0.0.0.0/0","Description":"HTTPS from internet"}]}]' >/dev/null
aws ec2 authorize-security-group-egress --group-id "$ALB_SG_ID" --ip-permissions \
  "[{\"IpProtocol\":\"tcp\",\"FromPort\":$NODE_PORT_FROM,\"ToPort\":$NODE_PORT_TO,\"UserIdGroupPairs\":[{\"GroupId\":\"$NODE_SG_ID\",\"Description\":\"To APISIX pods\"}]}]" >/dev/null

step "노드 SG 규칙: ALB에서 서비스 포트, 노드끼리 전체, 아웃바운드 전체(NAT)"
aws ec2 authorize-security-group-ingress --group-id "$NODE_SG_ID" --ip-permissions \
  "[{\"IpProtocol\":\"tcp\",\"FromPort\":$NODE_PORT_FROM,\"ToPort\":$NODE_PORT_TO,\"UserIdGroupPairs\":[{\"GroupId\":\"$ALB_SG_ID\",\"Description\":\"APISIX port from ALB\"}]},
    {\"IpProtocol\":\"-1\",\"UserIdGroupPairs\":[{\"GroupId\":\"$NODE_SG_ID\",\"Description\":\"All traffic between nodes\"}]}]" >/dev/null
aws ec2 authorize-security-group-egress --group-id "$NODE_SG_ID" --ip-permissions \
  '[{"IpProtocol":"-1","IpRanges":[{"CidrIp":"0.0.0.0/0","Description":"All outbound (via NAT)"}]}]' >/dev/null

step "완료. 다음: ./03-ecr.sh"
