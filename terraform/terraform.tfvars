# 엑셀 '변수' 시트와 대응. 값이 바뀌면 여기만 수정한다.
region  = "ap-northeast-2"
project = "osi7"

vpc_cidr = "10.20.0.0/16"
azs      = ["ap-northeast-2a", "ap-northeast-2c"]

public_subnet_cidrs = ["10.20.0.0/24", "10.20.1.0/24"]
app_subnet_cidrs    = ["10.20.10.0/24", "10.20.11.0/24"]
# DB 서브넷 없음: DB(MySQL 8.4)는 온프레미스에서만 운영

nat_gateway_count = 1


# 진입: ALB(Ingress, TLS 종료, target-type ip) -> APISIX. ALB가 APISIX Pod IP로 바로 보내므로 NodePort는 열지 않는다
# APISIX gateway HTTP 컨테이너 포트 (9080, 예찬님 확인 완료)
node_service_port_from = 9080
node_service_port_to   = 9080
# ALB 대상 상태 검사: APISIX 상태 엔드포인트 7085 /status/ready (예찬님 확인. Ingress backend는 Service apisix-gateway 포트 80)
alb_health_check_port = 7085

# ECR 리포지토리는 상시 루트 terraform/ecr에서 관리한다. 메인은 노드 Pull 권한 범위(<namespace>/*)만 쓴다
ecr_namespace = "ecommerce" # terraform/ecr과 같게

# EKS (AWS 쿠버네티스는 EKS로 확정)
eks_kubernetes_version = "1.36"          # 온프레미스 1.36.5와 같은 마이너 버전 (EKS는 패치 버전을 AWS가 관리)
eks_service_cidr       = "172.20.0.0/16" # 생성 후 변경 불가. 온프레미스 VCN 10.0.0.0/16, Pod 10.233.64.0/18, Service 10.233.0.0/18과 겹치지 않게
# API 서버 공개 접근 허용 IP. 팀원 공인 IP/32, 온프레미스 NAT 공인 IP/32를 넣는다. 비우면 VPC 안에서만 접근
eks_public_access_cidrs = [
  "140.238.24.33/32", # OCI private 서브넷 NAT Gateway (ArgoCD가 도는 cp-01, wk-01/02의 출구)
]
# 노드: 앱 Pod가 메모리 512Mi를 요청해 t3.small(2GiB)은 부족 (예찬님 계산: 평소 앱 requests CPU 2.2 / 4.5Gi, 최대 3.7 / 7.5Gi + 시스템)
# Free plan에서 쓸 수 있는 m7i-flex.large(2 vCPU / 8GiB)로 평소 2대, 최대 3대. 유료 플랜 전환 후 필요한 사양으로 변경
eks_node_instance_types = ["m7i-flex.large"]
eks_node_desired_size   = 2
eks_node_min_size       = 2
eks_node_max_size       = 3

# 팀원 kubectl 권한. 사용자는 terraform/iam-users가 만들므로 iam-users를 먼저 apply한다.
# 클러스터 생성자에게 자동으로 관리자를 주지 않으므로 명호도 여기 넣는다.
# 홍섭: kube-prometheus-stack 설치 때만 AmazonEKSClusterAdminPolicy(namespaces 없이)로 바꿔 apply하고, 설치 후 되돌린다
eks_access_entries = {
  myungho    = { policy = "AmazonEKSClusterAdminPolicy" }                                            # 명호: IaC
  yechan     = { policy = "AmazonEKSClusterAdminPolicy" }                                            # 예찬: KEDA, Metrics Server, Argo Rollouts가 클러스터 단위 설치
  jieun      = { policy = "AmazonEKSAdminPolicy", namespaces = ["ecommerce-main"] }                  # 지은: CI/CD
  hongseop   = { policy = "AmazonEKSAdminPolicy", namespaces = ["monitoring"] }                      # 홍섭: 관측성
  kwangryeol = { policy = "AmazonEKSViewPolicy" }                                                    # 광렬: 네트워크
  jaehak     = { policy = "AmazonEKSViewPolicy", extra_policies = { AmazonEKSEditPolicy = ["qa"] } } # 재학: QA. 전체 조회 + qa 네임스페이스에서 측정용 Pod·Job 생성/삭제
  junho      = { policy = "AmazonEKSViewPolicy", namespaces = ["ecommerce-main"] }                   # 준호: DB. 테스트 Pod가 필요하면 AmazonEKSEditPolicy
  # 온프레미스 ArgoCD가 EKS를 원격 클러스터(osi7-aws)로 등록해 쓰는 계정. 사용자는 iam-users가 만든다.
  # ArgoCD 클러스터 시크릿의 namespaces도 ecommerce-main, ingress-apisix로 맞춰야 한다 (권한이 그 네임스페이스에만 있음)
  # ingress-apisix: ALB Ingress (APISIX Service apisix-gateway와 같은 네임스페이스). APISIX 차트는 예찬님이 직접 설치
  osi7-argocd = { policy = "AmazonEKSAdminPolicy", namespaces = ["ecommerce-main", "ingress-apisix"] }
}
