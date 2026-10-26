# QA 가중치 전환 단계 온프레미스:AWS = 0:100
# terraform/dns에서: terraform apply -var-file=weights/0-100.tfvars
# 가중치는 비율이다 (온프레미스 몫 = 0 / (0 + 100)). 레코드 TTL이 60초라 반영까지 최대 1분 + 클라이언트 캐시
aws_ingress_enabled = true
onprem_weight       = 0
aws_weight          = 100
# switch_hosts(keycloak)는 가중치 없이 0:100에서만 AWS로 넘긴다
switch_target = "aws"
