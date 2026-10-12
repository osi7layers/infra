# 엑셀 '변수' 시트와 대응. 값이 바뀌면 여기만 수정한다.
region  = "ap-northeast-2"
project = "osi7"

vpc_cidr = "10.20.0.0/16"
azs      = ["ap-northeast-2a", "ap-northeast-2c"]

public_subnet_cidrs = ["10.20.0.0/24", "10.20.1.0/24"]
app_subnet_cidrs    = ["10.20.10.0/24", "10.20.11.0/24"]
db_subnet_cidrs     = ["10.20.20.0/24", "10.20.21.0/24"]

nat_gateway_count = 1

# 온프레미스 대역은 임시값. 광렬님께 확인 후 수정 (VPC 대역과 겹치면 안 됨)
onprem_cidr = "192.168.0.0/16"

# MySQL 8.4 LTS
db_port = 3306

# ALB -> Node 서비스 포트. APISIX/Gateway 포트가 정해지면 좁힌다 (임시: NodePort 범위)
node_service_port_from = 30000
node_service_port_to   = 32767

# ECR (Harbor와 환경별로 분리. AWS 환경은 ECR 사용)
ecr_namespace = "osi-shop" # Harbor 프로젝트 이름과 동일 (CI/CD 설계안 기준)
ecr_repositories = [
  "auth-service", "favourite-service", "inventory-service", "media-service",
  "notification-service", "order-service", "payment-service", "product-service",
  "promotion-service", "rating-service", "search-service", "shipping-service",
  "tax-service", "frontend-web", "frontend-admin",
]
ecr_image_tag_mutability = "IMMUTABLE"
ecr_keep_image_count     = 30
ecr_force_delete         = true

# EKS (AWS 쿠버네티스는 EKS로 확정)
eks_kubernetes_version = "1.36" # 온프레미스 1.36.5와 같은 마이너 버전 (EKS는 패치 버전을 AWS가 관리)
# API 서버 공개 접근 허용 IP. 팀원 공인 IP/32, 온프레미스 NAT 공인 IP/32를 넣는다. 비우면 VPC/VPN 안에서만 접근
eks_public_access_cidrs = []
eks_node_instance_types = ["t3.small"] # 테스트용 임시값. 실제 프로젝트에서는 사양 협의 후 변경 (프리 플랜: 프리 티어 대상 + 2a/2c 지원 타입만 가능, c7i-flex는 2a/2c 미지원)
eks_node_desired_size   = 2
eks_node_min_size       = 2
eks_node_max_size       = 4

# 팀원 kubectl 권한. 사용자는 terraform/iam-users가 만들므로 iam-users를 먼저 apply한다.
# 클러스터 생성자에게 자동으로 관리자를 주지 않으므로 명호도 여기 넣는다.
# 홍섭: kube-prometheus-stack 설치 때만 AmazonEKSClusterAdminPolicy(namespaces 없이)로 바꿔 apply하고, 설치 후 되돌린다
eks_access_entries = {
  myungho    = { policy = "AmazonEKSClusterAdminPolicy" }                                # 명호: IaC
  yechan     = { policy = "AmazonEKSClusterAdminPolicy" }                                # 예찬: KEDA, Metrics Server, Argo Rollouts가 클러스터 단위 설치
  jieun      = { policy = "AmazonEKSAdminPolicy", namespaces = ["argocd", "ecommerce"] } # 지은: CI/CD
  hongseop   = { policy = "AmazonEKSAdminPolicy", namespaces = ["monitoring"] }          # 홍섭: 관측성
  kwangryeol = { policy = "AmazonEKSViewPolicy" }                                        # 광렬: 네트워크
  jaehak     = { policy = "AmazonEKSViewPolicy" }                                        # 재학: QA
  junho      = { policy = "AmazonEKSViewPolicy", namespaces = ["ecommerce"] }            # 준호: DB. 테스트 Pod가 필요하면 AmazonEKSEditPolicy
}
