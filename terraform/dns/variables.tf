variable "region" {
  description = "AWS 리전 (메인 terraform과 동일). Route 53은 글로벌 서비스라 영역 자체와는 무관"
  type        = string
  default     = "ap-northeast-2"
}

variable "project" {
  description = "프로젝트 이름 (IAM 이름 접두사, 태그)"
  type        = string
  default     = "osi7"
}

variable "domain" {
  description = "Route 53에 위임할 도메인. 가비아에서 이 도메인의 네임서버를 Route 53 값으로 바꾼다"
  type        = string
  default     = "osi7.shop"
}

variable "harbor_ip" {
  description = "harbor.<domain> A 레코드 값 (harbor-01의 Tailscale IP, 100.x.x.x). 비우면 레코드를 만들지 않는다"
  type        = string
  default     = ""

  validation {
    condition     = var.harbor_ip == "" || can(cidrhost("${var.harbor_ip}/32", 0))
    error_message = "IPv4 주소 형식이어야 합니다 (예: 100.64.0.10)."
  }
}

variable "create_acme_user" {
  description = "인증서 자동 갱신용 IAM 사용자 생성 여부. 첫 발급(수동 TXT) 후 true로 바꿔 apply한다"
  type        = bool
  default     = false
}

variable "acme_hosts" {
  description = "자동 갱신 사용자가 TXT를 바꿀 수 있는 호스트 이름 (_acme-challenge.<호스트>.<domain>)"
  type        = list(string)
  default     = ["harbor"]
}
