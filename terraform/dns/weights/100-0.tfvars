# QA 가중치 전환 단계 온프레미스:AWS = 100:0. 시작 단계이자 롤백 파일
# terraform/dns에서: terraform apply -var-file=weights/100-0.tfvars
# 가중치는 비율이다 (온프레미스 몫 = 100 / (100 + 0)). 레코드 TTL이 60초라 반영까지 최대 1분 + 클라이언트 캐시
aws_ingress_enabled = true
onprem_weight       = 100
aws_weight          = 0
