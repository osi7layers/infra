# terraform init -backend-config=backend.hcl 로 사용한다.
# 메인(terraform/)과 같은 버킷을 쓰고 key만 다르게 해서 state를 분리한다.
# 메인을 destroy해도 호스팅 영역이 남아서 가비아 네임서버 등록을 다시 하지 않아도 된다.
bucket       = "osi7-tfstate-918633123181"
key          = "dns/terraform.tfstate"
region       = "ap-northeast-2"
encrypt      = true
use_lockfile = true
