# terraform init -backend-config=backend.hcl 로 사용한다.
# 메인(terraform/)과 같은 버킷을 쓰고 key만 다르게 해서 state를 분리한다.
# 메인을 destroy해도 VPN 연결이 남아서 AWS 쪽 터널 IP가 바뀌지 않는다.
bucket       = "osi7-tfstate-918633123181"
key          = "vpn/terraform.tfstate"
region       = "ap-northeast-2"
encrypt      = true
use_lockfile = true
