variable "region" {
  description = "AWS 리전"
  type        = string
  default     = "ap-northeast-2"
}

variable "project" {
  description = "프로젝트 이름 (리소스 이름 접두사, 태그)"
  type        = string
  default     = "osi7"
}

variable "vpc_cidr" {
  description = "VPC 대역. 온프레미스 대역과 겹치면 안 됨"
  type        = string
  default     = "10.20.0.0/16"
}

variable "azs" {
  description = "사용할 가용 영역 (2개)"
  type        = list(string)
  default     = ["ap-northeast-2a", "ap-northeast-2c"]
}

variable "public_subnet_cidrs" {
  description = "Public 서브넷 CIDR (azs 순서와 동일)"
  type        = list(string)
  default     = ["10.20.0.0/24", "10.20.1.0/24"]
}

variable "app_subnet_cidrs" {
  description = "Private App 서브넷 CIDR (azs 순서와 동일)"
  type        = list(string)
  default     = ["10.20.10.0/24", "10.20.11.0/24"]
}

variable "nat_gateway_count" {
  description = "NAT Gateway 개수. 1이면 저렴하지만 단일 장애점, 2이면 AZ별 1개"
  type        = number
  default     = 1
}

variable "node_service_port_from" {
  description = "ALB가 APISIX Pod로 보내는 포트 범위 시작 (target-type ip라 NodePort가 아니라 Pod 포트). APISIX gateway HTTP 기본 9080"
  type        = number
  default     = 9080
}

variable "node_service_port_to" {
  description = "ALB가 APISIX Pod로 보내는 포트 범위 끝"
  type        = number
  default     = 9080
}

variable "ecr_repositories" {
  description = "ECR 리포지토리 이름 목록 (백엔드 4개 + 프론트엔드 web). 이름은 Harbor 리포지토리 이름과 맞춘다"
  type        = list(string)
  default     = ["auth", "product", "order", "promotion", "web"]
}

variable "ecr_image_tag_mutability" {
  description = "IMMUTABLE이면 같은 태그 재푸시 불가. CI/CD가 latest를 덮어쓰면 MUTABLE로 변경"
  type        = string
  default     = "IMMUTABLE"
}

variable "ecr_keep_image_count" {
  description = "리포지토리마다 보관할 최근 이미지 수 (push 순서 기준). 롤백할 버전은 최근 10번 push 안에 있어야 함"
  type        = number
  default     = 10
}

variable "ecr_force_delete" {
  description = "true이면 이미지가 있어도 destroy 가능 (재구축 리허설용)"
  type        = bool
  default     = true
}

variable "ecr_namespace" {
  description = "ECR 리포지토리 이름 접두사. Harbor 프로젝트 이름과 동일하게 (CI/CD: ecommerce)"
  type        = string
  default     = "ecommerce"
}

variable "eks_service_cidr" {
  description = "EKS Service(ClusterIP) 대역. 클러스터를 만든 뒤에는 바꿀 수 없다. VPC와 온프레미스(VCN 10.0.0.0/16, Pod 10.233.64.0/18, Service 10.233.0.0/18)와 겹치면 안 됨"
  type        = string
  default     = "172.20.0.0/16"
}

variable "eks_kubernetes_version" {
  description = "EKS 쿠버네티스 버전(마이너까지만 지정). 온프레미스 1.36.5와 맞춤"
  type        = string
  default     = "1.36"
}

variable "eks_public_access_cidrs" {
  description = "EKS API 공개 접근 허용 CIDR (팀원/온프레미스 공인 IP/32). 비우면 VPC 안에서만 접근"
  type        = list(string)
  default     = ["140.238.24.33/32"]
}

variable "eks_node_instance_types" {
  description = "EKS 노드 인스턴스 타입 (Free plan 임시: m7i-flex.large). 프리 플랜 계정이라 프리 티어 대상 + 2a/2c 지원 타입만 가능. 유료 플랜 전환 후 필요한 사양으로 변경"
  type        = list(string)
  default     = ["m7i-flex.large"]
}

variable "eks_node_desired_size" {
  type    = number
  default = 2
}

variable "eks_node_min_size" {
  type    = number
  default = 2
}

variable "eks_node_max_size" {
  type    = number
  default = 3
}

variable "eks_access_entries" {
  description = "팀원 kubectl 권한 (IAM 사용자 이름 -> EKS 액세스 정책, 네임스페이스). 사용자는 terraform/iam-users가 만든다"
  type = map(object({
    policy     = string
    namespaces = optional(list(string), [])
  }))
  default = {
    myungho     = { policy = "AmazonEKSClusterAdminPolicy" }
    yechan      = { policy = "AmazonEKSClusterAdminPolicy" }
    jieun       = { policy = "AmazonEKSAdminPolicy", namespaces = ["ecommerce-main"] }
    hongseop    = { policy = "AmazonEKSAdminPolicy", namespaces = ["monitoring"] }
    kwangryeol  = { policy = "AmazonEKSViewPolicy" }
    jaehak      = { policy = "AmazonEKSViewPolicy" }
    junho       = { policy = "AmazonEKSViewPolicy", namespaces = ["ecommerce-main"] }
    osi7-argocd = { policy = "AmazonEKSAdminPolicy", namespaces = ["ecommerce-main"] }
  }
}
