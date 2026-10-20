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
  description = "Route 53에 위임한 도메인. 이 이름의 퍼블릭 호스팅 영역이 콘솔에서 먼저 만들어져 있어야 한다"
  type        = string
  default     = "osi7.shop"
}

variable "private_hosts" {
  description = "OCI private IP로 접속하는 온프레미스 호스트 (호스트 이름 -> 10.0.1.x). <호스트>.<domain> A 레코드를 만든다"
  type        = map(string)
  default     = {}

  validation {
    condition     = alltrue([for ip in values(var.private_hosts) : can(cidrhost("${ip}/32", 0))])
    error_message = "IPv4 주소 형식이어야 합니다 (예: 10.0.1.94)."
  }
}

variable "create_acme_user" {
  description = "인증서 자동 갱신용 IAM 사용자 생성 여부. 첫 발급(수동 TXT) 후 true로 바꿔 apply한다"
  type        = bool
  default     = false
}

variable "acme_hosts" {
  description = "자동 갱신 사용자가 TXT를 바꿀 수 있는 호스트 이름 (_acme-challenge.<호스트>.<domain>). 온프레미스 인증서용. 와일드카드 인증서 *.dev.<domain>의 TXT 이름은 _acme-challenge.dev.<domain>이라 dev로 적는다. *를 쓸 수 있다 (*.dev = 개발 호스트별 인증서 keycloak.dev 등)"
  type        = list(string)
  default     = ["harbor", "shop", "api", "keycloak", "grafana", "dev", "*.dev"]
}

variable "acm_hosts" {
  description = "AWS 쪽 ALB에 붙일 ACM 인증서의 호스트 이름 (첫 번째가 대표 이름, 나머지는 SAN)"
  type        = list(string)
  default     = ["shop", "api"]

  validation {
    condition     = length(var.acm_hosts) > 0
    error_message = "호스트 이름이 하나 이상 있어야 합니다."
  }
}

variable "onprem_public_ip" {
  description = "온프레미스 진입 공인 IP (네트워크 담당 제공). acm_hosts의 온프레미스 가중치 레코드와 onprem_hosts 레코드 값. 비우면 만들지 않는다"
  type        = string
  default     = ""

  validation {
    condition     = var.onprem_public_ip == "" || can(cidrhost("${var.onprem_public_ip}/32", 0))
    error_message = "IPv4 주소 형식이어야 합니다 (예: 203.0.113.10)."
  }
}

variable "onprem_hosts" {
  description = "온프레미스에만 있는 호스트 (onprem_public_ip로 단순 A 레코드). 와일드카드도 된다 (예: *.dev -> *.dev.osi7.shop)"
  type        = list(string)
  default     = ["keycloak", "*.dev"]
}

variable "onprem_weight" {
  description = "acm_hosts 가중치 레코드의 온프레미스 쪽 가중치 (0~255)"
  type        = number
  default     = 100

  validation {
    condition     = var.onprem_weight >= 0 && var.onprem_weight <= 255
    error_message = "가중치는 0~255 사이여야 합니다."
  }
}

variable "aws_weight" {
  description = "acm_hosts 가중치 레코드의 AWS 쪽 가중치 (0~255). 온프레미스와 합이 0이면 양쪽에 똑같이 나뉘므로 막는다"
  type        = number
  default     = 0

  validation {
    condition     = var.aws_weight >= 0 && var.aws_weight <= 255
    error_message = "가중치는 0~255 사이여야 합니다."
  }

  validation {
    condition     = var.aws_weight + var.onprem_weight > 0
    error_message = "onprem_weight와 aws_weight가 둘 다 0일 수 없습니다."
  }
}

variable "aws_ingress_enabled" {
  description = "AWS 쪽 가중치 레코드 생성 여부. 메인 apply 후 LB Controller가 LB를 만든 뒤 true, 메인 destroy 전에 false로 apply"
  type        = bool
  default     = false
}

variable "aws_lb_tags" {
  description = "AWS 쪽 LB를 찾는 태그 (정확히 1개만 맞아야 함). ALB가 여러 개면 ingress.k8s.aws/stack(IngressGroup 이름) 태그를 추가"
  type        = map(string)
  default     = { "elbv2.k8s.aws/cluster" = "osi7-eks" }
}

variable "onprem_health_check_path" {
  description = "온프레미스 상태 검사 경로 (예: /healthz). 값이 있고 onprem_public_ip도 있으면 HTTPS 상태 검사를 만들어 온프레미스 레코드에 붙인다"
  type        = string
  default     = ""

  validation {
    condition     = var.onprem_health_check_path == "" || startswith(var.onprem_health_check_path, "/")
    error_message = "경로는 /로 시작해야 합니다."
  }
}

variable "onprem_health_check_interval" {
  description = "온프레미스 상태 검사 간격(초). 30(표준) 또는 10(빠른 간격, 비용 추가). 장애 감지 시간은 대략 간격 x 실패 횟수"
  type        = number
  default     = 30

  validation {
    condition     = contains([10, 30], var.onprem_health_check_interval)
    error_message = "10 또는 30만 가능합니다."
  }
}

variable "onprem_health_check_failure_threshold" {
  description = "온프레미스를 비정상으로 판단할 연속 실패 횟수 (1~10)"
  type        = number
  default     = 3

  validation {
    condition     = var.onprem_health_check_failure_threshold >= 1 && var.onprem_health_check_failure_threshold <= 10
    error_message = "1~10 사이여야 합니다."
  }
}
