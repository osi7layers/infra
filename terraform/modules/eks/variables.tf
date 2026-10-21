variable "project" {
  type = string
}

variable "cluster_name" {
  description = "EKS 클러스터 이름"
  type        = string
}

variable "service_ipv4_cidr" {
  description = "Service(ClusterIP) 대역. 클러스터를 만든 뒤에는 바꿀 수 없다"
  type        = string
  default     = "172.20.0.0/16"
}

variable "kubernetes_version" {
  description = "쿠버네티스 마이너 버전 (예: 1.36). 패치 버전은 EKS가 관리"
  type        = string
  default     = "1.36"
}

variable "subnet_ids" {
  description = "컨트롤 플레인 ENI와 노드가 놓일 Private App 서브넷 (AZ 2개 이상)"
  type        = list(string)
}

variable "cluster_role_arn" {
  type = string
}

variable "node_role_arn" {
  type = string
}

variable "node_sg_id" {
  description = "security 모듈의 노드 SG. 노드에 EKS 클러스터 SG와 함께 붙인다"
  type        = string
}

variable "public_access_cidrs" {
  description = "API 서버 공개 접근을 허용할 CIDR(예: 팀원 공인 IP/32, 온프레미스 NAT IP/32). 비우면 공개 엔드포인트를 끄고 VPC/VPN 안에서만 접근"
  type        = list(string)
  default     = []
}

variable "log_retention_days" {
  type    = number
  default = 30
}

variable "node_instance_types" {
  description = "노드 인스턴스 타입. 서브넷 AZ(2a/2c)에서 지원되는 타입이어야 함"
  type        = list(string)
  default     = ["m7i-flex.large"]
}

variable "node_desired_size" {
  type    = number
  default = 2
}

variable "node_min_size" {
  type    = number
  default = 2
}

variable "node_max_size" {
  type    = number
  default = 3
}

variable "node_disk_size_gb" {
  type    = number
  default = 30
}

variable "access_entries" {
  description = "kubectl 권한을 줄 IAM 사용자 이름 -> EKS 액세스 정책(AmazonEKSClusterAdminPolicy 등)과 네임스페이스. namespaces가 비면 클러스터 전체. extra_policies는 네임스페이스에만 더 주는 정책"
  type = map(object({
    policy         = string
    namespaces     = optional(list(string), [])
    extra_policies = optional(map(list(string)), {}) # 추가 정책 -> 네임스페이스 (네임스페이스 범위로만 붙는다)
  }))
  default = {}
}
