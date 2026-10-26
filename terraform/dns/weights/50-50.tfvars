# QA 가중치 전환 단계 온프레미스:AWS = 50:50
# terraform/dns에서: terraform apply -var-file=weights/50-50.tfvars
# 가중치는 비율이다 (온프레미스 몫 = 50 / (50 + 50)). 레코드 TTL이 60초라 반영까지 최대 1분 + 클라이언트 캐시
aws_ingress_enabled = true
onprem_weight       = 50
aws_weight          = 50
