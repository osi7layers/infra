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

variable "db_subnet_cidrs" {
  description = "Private DB 서브넷 CIDR (azs 순서와 동일)"
  type        = list(string)
  default     = ["10.20.20.0/24", "10.20.21.0/24"]
}

variable "nat_gateway_count" {
  description = "NAT Gateway 개수. 1이면 저렴하지만 단일 장애점, 2이면 AZ별 1개"
  type        = number
  default     = 1
}

variable "onprem_cidr" {
  description = "온프레미스 대역. 광렬님께 확인 후 확정 (임시값). VPC 대역과 겹치면 VPN 불가"
  type        = string
  default     = "192.168.0.0/16"
}

variable "db_port" {
  description = "DB 접속 포트. MySQL 8.4 LTS 3306"
  type        = number
  default     = 3306
}

variable "node_service_port_from" {
  description = "ALB가 Node로 보내는 서비스 포트 범위 시작. 예찬님과 확정 후 변경 (임시: NodePort 범위)"
  type        = number
  default     = 30000
}

variable "node_service_port_to" {
  description = "ALB가 Node로 보내는 서비스 포트 범위 끝"
  type        = number
  default     = 32767
}

variable "ecr_repositories" {
  description = "ECR 리포지토리 이름 목록 (샘플 앱의 서비스 13개 + 프론트엔드 2개)"
  type        = list(string)
  default = [
    "auth-service", "favourite-service", "inventory-service", "media-service",
    "notification-service", "order-service", "payment-service", "product-service",
    "promotion-service", "rating-service", "search-service", "shipping-service",
    "tax-service", "frontend-web", "frontend-admin",
  ]
}

variable "ecr_image_tag_mutability" {
  description = "IMMUTABLE이면 같은 태그 재푸시 불가. CI/CD가 latest를 덮어쓰면 MUTABLE로 변경"
  type        = string
  default     = "IMMUTABLE"
}

variable "ecr_keep_image_count" {
  description = "리포지토리마다 보관할 최근 이미지 수"
  type        = number
  default     = 30
}

variable "ecr_force_delete" {
  description = "true이면 이미지가 있어도 destroy 가능 (재구축 리허설용)"
  type        = bool
  default     = true
}

variable "ecr_namespace" {
  description = "ECR 리포지토리 이름 접두사. Harbor 프로젝트 이름과 동일하게 (CI/CD 설계안: osi-shop)"
  type        = string
  default     = "osi-shop"
}

variable "eks_kubernetes_version" {
  description = "EKS 쿠버네티스 버전(마이너까지만 지정). 온프레미스 1.36.5와 맞춤"
  type        = string
  default     = "1.36"
}

variable "eks_public_access_cidrs" {
  description = "EKS API 공개 접근 허용 CIDR (팀원/온프레미스 공인 IP/32). 비우면 VPC·VPN 안에서만 접근"
  type        = list(string)
  default     = []
}

variable "eks_node_instance_types" {
  description = "EKS 노드 인스턴스 타입 (테스트용 임시: t3.small). 프리 플랜 계정이라 프리 티어 대상 + 2a/2c 지원 타입만 가능 (m7i-flex.large, t3.small 등)"
  type        = list(string)
  default     = ["t3.small"]
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
  default = 4
}

variable "eks_access_entries" {
  description = "팀원 kubectl 권한 (IAM 사용자 이름 -> EKS 액세스 정책, 네임스페이스). 사용자는 terraform/iam-users가 만든다"
  type = map(object({
    policy     = string
    namespaces = optional(list(string), [])
  }))
  default = {
    yechan     = { policy = "AmazonEKSClusterAdminPolicy" }
    jieun      = { policy = "AmazonEKSAdminPolicy", namespaces = ["argocd", "ecommerce"] }
    hongseop   = { policy = "AmazonEKSAdminPolicy", namespaces = ["monitoring"] }
    kwangryeol = { policy = "AmazonEKSViewPolicy" }
    jaehak     = { policy = "AmazonEKSViewPolicy" }
    junho      = { policy = "AmazonEKSViewPolicy", namespaces = ["ecommerce"] }
  }
}
