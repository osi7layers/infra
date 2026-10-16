# harbor-01의 Tailscale IP (온프레미스 담당 제공). tailnet 안의 기기에서만 접속된다
harbor_ip = "100.85.182.121"

# Harbor 인증서 자동 갱신용 사용자 (첫 발급은 2026-10-14 수동 TXT로 완료)
create_acme_user = true

# 온프레미스 인증서 자동 갱신 대상 (_acme-challenge.<호스트>.osi7.shop TXT만 바꿀 수 있음)
acme_hosts = ["harbor", "shop", "api", "keycloak"]

# AWS 쪽 NLB용 ACM 인증서 (shop.osi7.shop + api.osi7.shop). 이 호스트들이 온프레미스/AWS 가중치 레코드도 된다
acm_hosts = ["shop", "api"]

# 온프레미스 진입 공인 IP (네트워크 담당 확인 대기). 비어 있으면 온프레미스 레코드를 만들지 않는다
onprem_public_ip = ""
onprem_hosts     = ["keycloak"] # 온프레미스에만 있는 호스트

# 가중치 전환 단계 (온프레미스:AWS). 숫자 두 개만 바꿔 apply한다
#   1단계 100:0 -> 2단계 95:5 -> 3단계 50:50 -> 4단계 0:100
onprem_weight = 100
aws_weight    = 0

# 메인 apply 후 LB Controller가 LB를 만들면 true. 메인 destroy 전에 false로 apply
aws_ingress_enabled = false
aws_lb_tags         = { "elbv2.k8s.aws/cluster" = "osi7-eks" }

# 온프레미스 상태 검사 경로 (온프레미스 구성 후 네트워크 담당이 정함). 비우면 상태 검사 없음
onprem_health_check_path = ""
