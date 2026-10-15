# harbor-01의 Tailscale IP (온프레미스 담당 제공). tailnet 안의 기기에서만 접속된다
harbor_ip = "100.85.182.121"

# Harbor 인증서 자동 갱신용 사용자 (첫 발급은 2026-10-14 수동 TXT로 완료)
create_acme_user = true

# 온프레미스 인증서 자동 갱신 대상 (_acme-challenge.<호스트>.osi7.shop TXT만 바꿀 수 있음)
acme_hosts = ["harbor", "shop", "api", "keycloak"]

# AWS 쪽 NLB용 ACM 인증서 (shop.osi7.shop + api.osi7.shop)
acm_hosts = ["shop", "api"]
