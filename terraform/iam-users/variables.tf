variable "region" {
  description = "AWS 리전 (메인 terraform과 동일)"
  type        = string
  default     = "ap-northeast-2"
}

variable "project" {
  description = "프로젝트 이름 (그룹·정책 이름 접두사, 태그)"
  type        = string
  default     = "osi7"
}

variable "ecr_namespace" {
  description = "cicd 그룹이 push할 수 있는 ECR 리포지토리 접두사 (메인의 ecr_namespace와 같게)"
  type        = string
  default     = "osi-shop"
}

# 키는 IAM 사용자 이름. 메인의 eks_access_entries도 같은 이름을 쓴다.
# 그룹: infra-admin, network, k8s-operator, cicd, observability, readonly, qa-k6
# 루트 계정은 프로젝트에 쓰지 않는다. Terraform도 myungho(infra-admin)의 액세스 키로 실행한다.
variable "users" {
  description = "팀원 IAM 사용자 이름 -> 소속 그룹 목록"
  type        = map(list(string))
  default = {
    myungho    = ["infra-admin"]       # 명호: IaC (Terraform 실행)
    kwangryeol = ["network"]           # 광렬: 네트워크(VPN, Route 53)
    yechan     = ["k8s-operator"]      # 예찬: 워크로드/스케일링
    jieun      = ["cicd"]              # 지은: CI/CD
    hongseop   = ["observability"]     # 홍섭: 관측성
    jaehak     = ["readonly", "qa-k6"] # 재학: QA (k6 EC2 시작/중지)
    junho      = ["readonly"]          # 준호: DB
  }
}

variable "k6_instance_tag" {
  description = "qa-k6 그룹이 시작/중지할 수 있는 EC2의 태그 (Key=Value)"
  type        = object({ key = string, value = string })
  default     = { key = "Purpose", value = "k6" }
}
