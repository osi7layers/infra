# OCI private IP로 접속하는 온프레미스 호스트. OCI VCN 안(그리고 VPN으로 연결된 AWS)에서만 접속된다
private_hosts = {
  harbor  = "10.0.1.94"  # harbor-01
  grafana = "10.0.1.112" # mon-01 (관측성)
}

# Harbor 인증서 자동 갱신용 사용자 (첫 발급은 2026-10-14 수동 TXT로 완료)
create_acme_user = true

# 온프레미스 인증서 자동 갱신 대상 (_acme-challenge.<호스트>.osi7.shop TXT만 바꿀 수 있음)
# dev = 개발 환경 와일드카드 인증서 *.dev.osi7.shop (TXT 이름이 _acme-challenge.dev.osi7.shop)
acme_hosts = ["harbor", "shop", "api", "keycloak", "grafana", "dev"]

# AWS 쪽 LB(NLB 또는 ALB)용 ACM 인증서 (shop.osi7.shop + api.osi7.shop). 이 호스트들이 온프레미스/AWS 가중치 레코드도 된다
acm_hosts = ["shop", "api"]

# 온프레미스 진입 공인 IP (OCI edge-proxy, 고정 IP). 비어 있으면 온프레미스 레코드를 만들지 않는다
onprem_public_ip = "132.145.89.131"
# 온프레미스에만 있는 호스트. *.dev는 OCI 개발 환경 와일드카드 (shop.dev, api.dev, keycloak.dev 등.
# web이 화면 주소 맨 앞을 api로 바꿔 API 주소를 정하므로 개발도 shop.dev / api.dev처럼 같은 단계로 맞춤)
onprem_hosts = ["keycloak", "*.dev"]

# 가중치 (온프레미스:AWS). 평소 값은 여기, QA 전환 단계는 weights/ 파일로 apply한다
#   terraform apply -var-file=weights/50-50.tfvars   (롤백: weights/100-0.tfvars)
onprem_weight = 100
aws_weight    = 0

# 메인 apply 후 LB Controller가 LB를 만들면 true. 메인 destroy 전에 false로 apply
aws_ingress_enabled = false
aws_lb_tags         = { "elbv2.k8s.aws/cluster" = "osi7-eks" }

# 온프레미스 상태 검사 경로 (/healthz 200으로 확정). OCI 앱이 올라가 /healthz가 200을 주면 "/healthz"로 바꿔 apply. 비우면 상태 검사 없음
onprem_health_check_path = ""
# 상태 검사 간격(초, 30 또는 10)과 실패 횟수. 감지 시간은 대략 간격 x 횟수 (QA 간격별 비교용)
onprem_health_check_interval          = 30
onprem_health_check_failure_threshold = 3
