#!/usr/bin/env bash
# 메인 apply 후 클러스터 단위 구성 요소를 설치한다 (Terraform은 IAM 역할과 Pod Identity 연결까지만 만든다).
#   - AWS Load Balancer Controller: Ingress를 보고 ALB를 만든다 (kube-system/aws-load-balancer-controller)
#   - Cluster Autoscaler: Pod가 Pending이면 노드 그룹을 min~max 안에서 늘린다 (kube-system/cluster-autoscaler)
#   - 기본 StorageClass gp3(암호화). EBS CSI 드라이버는 Terraform 애드온이다 (2026-10-22 기준 AWS에서 PVC를 쓰는 앱은 없음)
#   - 네임스페이스 ecommerce-main(앱), ingress-apisix(APISIX·Ingress). ArgoCD 권한이 이 둘에만 있어서 미리 만든다
#     액세스 정책에 없는 CRD 리소스(HTTPRoute 등) 권한도 두 네임스페이스에 RBAC로 더한다 (manifests/argocd-rbac.yaml)
#   - 앱 배포에 필요한 플랫폼 (온프렘과 같은 버전·값, scripts/manifests/): Gateway API·APISIX CRD -> APISIX -> Gateway -> KEDA -> Argo Rollouts -> metrics-server
#     ArgoCD는 네임스페이스 권한만 있어서 CRD와 클러스터 단위 리소스(GatewayClass 등)를 만들 수 없으므로 여기서 설치한다.
#
# 사용법 (terraform 폴더에서, Git Bash):
#   ./scripts/install-controllers.sh           # kubeconfig 설정 -> 두 컨트롤러 설치(또는 같은 버전으로 다시 적용) -> 상태 확인
#   ./scripts/install-controllers.sh --status  # 설치 없이 상태만 확인 (내리기 전 ALB·PVC·EBS가 0인지도 여기서 본다)
#
# Helm 설치를 Terraform에 넣지 않은 이유: destroy할 때 컨트롤러가 먼저 지워지면 ALB가 남아 VPC 삭제가 실패한다.
# 내릴 때는 dns aws_ingress_enabled=false apply -> ArgoCD 앱 삭제(Ingress·PVC) -> ALB·EBS 삭제 확인(--status) -> terraform destroy 순서로 하고,
# 컨트롤러는 따로 지우지 않는다 (클러스터와 함께 지워진다). ALB와 PVC의 EBS는 컨트롤러·드라이버가 살아 있을 때 지워야 같이 없어진다.
#
# 필요한 도구: aws, terraform, kubectl, helm (winget install Kubernetes.kubectl / Helm.Helm)
set -euo pipefail
cd "$(dirname "$0")/.."

# 버전 고정. LB Controller를 올리면 modules/eks/policies/aws-load-balancer-controller.json도 같은 버전으로 바꾼다.
LBC_CHART_VERSION="3.6.0"  # 앱 v3.6.0 (정책 파일과 같은 버전)
CA_CHART_VERSION="9.59.0"  # 차트 기본 이미지는 1.35라서 이미지 태그를 클러스터 마이너 버전에 맞춘다
CA_IMAGE_TAG="v1.36.1"     # Cluster Autoscaler는 쿠버네티스 마이너 버전(eks_kubernetes_version 1.36)과 맞춰야 한다
# 플랫폼 버전은 온프렘 클러스터에 실제 설치된 것과 같게 둔다 (2026-10-26 광렬님·예찬님 확인)
APISIX_CHART_VERSION="2.18.2"   # APISIX 3.19.0, Ingress Controller 2.2.0. Gateway API CRD v1.6.0 standard가 차트에 들어 있다
KEDA_CHART_VERSION="2.21.0"
ROLLOUTS_CHART_VERSION="2.43.6" # 이미지 v1.10.1, Gateway API 플러그인 v0.17.0 (manifests/argo-rollouts-values.yaml)
METRICS_SERVER_VERSION="v0.9.0" # 공식 components.yaml 그대로 (예찬님 10-27 설치와 같음). HPA·KEDA CPU 기준, kubectl top에 필요
REGION="${AWS_REGION:-ap-northeast-2}"
MANIFESTS="scripts/manifests"

# winget으로 설치한 kubectl·helm이 Git Bash PATH에 없을 때를 대비한다
WINGET_LINKS="$HOME/AppData/Local/Microsoft/WinGet/Links"
[ -d "$WINGET_LINKS" ] && PATH="$PATH:$WINGET_LINKS"
for tool in aws terraform kubectl helm openssl; do
  command -v "$tool" >/dev/null 2>&1 || { echo "$tool 이(가) 없습니다."; exit 1; }
done

step() { echo; echo "=== $*"; }

CLUSTER=$(terraform output -raw eks_cluster_name 2>/dev/null) || { echo "메인 state에 eks_cluster_name 출력이 없습니다. 메인을 먼저 apply하세요"; exit 1; }
VPC_ID=$(terraform output -raw vpc_id)

status() {
  step "노드"
  kubectl get nodes -o wide
  step "컨트롤러 Pod (kube-system)"
  kubectl -n kube-system get pods -l 'app.kubernetes.io/name in (aws-load-balancer-controller, aws-cluster-autoscaler)' -o wide
  step "Pod Identity 연결"
  aws eks list-pod-identity-associations --cluster-name "$CLUSTER" --region "$REGION" \
    --query 'associations[].[namespace, serviceAccount]' --output text | tr -d '\r'
  step "Cluster Autoscaler 최근 로그 (노드 그룹을 찾았는지)"
  kubectl -n kube-system logs deploy/cluster-autoscaler-aws-cluster-autoscaler --tail=20 2>/dev/null | grep -iE "nodegroup|asg|error" || echo "(로그 없음)"
  step "StorageClass"
  kubectl get storageclass
  step "플랫폼 Pod (APISIX, KEDA, Argo Rollouts)"
  kubectl get pods -n ingress-apisix -o wide 2>/dev/null
  kubectl get pods -n keda 2>/dev/null
  kubectl get pods -n argo-rollouts 2>/dev/null
  kubectl -n kube-system get deploy metrics-server 2>/dev/null
  step "Gateway (PROGRAMMED가 True여야 HTTPRoute가 붙는다)"
  kubectl get gatewayclass,gateway -A 2>/dev/null || echo "(Gateway API CRD 없음)"
  step "네임스페이스 라벨"
  kubectl get namespace ecommerce-main ingress-apisix --show-labels 2>/dev/null || true
  # destroy는 Terraform 밖에서 생긴 ALB와 EBS를 지우지 않는다. 내리기 전에 셋 다 0이어야 한다
  step "내리기 전 확인: Terraform 밖 리소스 (destroy 전에 모두 0)"
  echo "ALB (이 VPC):           $(aws elbv2 describe-load-balancers --region "$REGION" --query "length(LoadBalancers[?VpcId=='$VPC_ID'])" --output text | tr -d '\r')"
  echo "PVC (전체 네임스페이스): $(kubectl get pvc -A --no-headers 2>/dev/null | wc -l)"
  echo "EBS CSI 볼륨:           $(aws ec2 describe-volumes --region "$REGION" --filters Name=tag:ebs.csi.aws.com/cluster,Values=true --query 'length(Volumes)' --output text | tr -d '\r')"
}

step "kubeconfig: $CLUSTER ($REGION)"
aws eks update-kubeconfig --name "$CLUSTER" --region "$REGION" >/dev/null
kubectl get nodes >/dev/null

if [ "${1:-}" = "--status" ]; then
  status
  exit 0
fi

step "Helm 저장소"
helm repo add eks https://aws.github.io/eks-charts >/dev/null 2>&1 || true
helm repo add autoscaler https://kubernetes.github.io/autoscaler >/dev/null 2>&1 || true
helm repo add apisix https://charts.apiseven.com >/dev/null 2>&1 || true
helm repo add kedacore https://kedacore.github.io/charts >/dev/null 2>&1 || true
helm repo add argo https://argoproj.github.io/argo-helm >/dev/null 2>&1 || true
helm repo update eks autoscaler apisix kedacore argo >/dev/null

# 권한은 Pod Identity로 받으므로 서비스 계정에 역할 annotation(IRSA)을 넣지 않는다. 서비스 계정 이름은 Terraform의 연결과 같아야 한다.
# defaultTags: ALB·대상 그룹에 Project 태그를 붙여 Cost Explorer 비용 할당 태그로 모은다 (QA 비용 측정)
step "AWS Load Balancer Controller $LBC_CHART_VERSION"
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  --namespace kube-system --version "$LBC_CHART_VERSION" \
  --set clusterName="$CLUSTER" \
  --set region="$REGION" \
  --set vpcId="$VPC_ID" \
  --set serviceAccount.create=true \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set defaultTags.Project=osi7 \
  --wait --timeout 5m
# 다시 실행하면 차트가 웹훅 인증서를 새로 만들지만 떠 있는 Pod는 예전 인증서를 계속 써서, 모든 Service 생성이
# "x509: certificate signed by unknown authority"로 실패한다 (2026-10-26 발생). 재시작해 새 인증서를 읽게 한다
kubectl -n kube-system rollout restart deploy/aws-load-balancer-controller
kubectl -n kube-system rollout status deploy/aws-load-balancer-controller --timeout=3m

step "Cluster Autoscaler $CA_CHART_VERSION (이미지 $CA_IMAGE_TAG)"
helm upgrade --install cluster-autoscaler autoscaler/cluster-autoscaler \
  --namespace kube-system --version "$CA_CHART_VERSION" \
  --set cloudProvider=aws \
  --set awsRegion="$REGION" \
  --set autoDiscovery.clusterName="$CLUSTER" \
  --set image.tag="$CA_IMAGE_TAG" \
  --set rbac.serviceAccount.create=true \
  --set rbac.serviceAccount.name=cluster-autoscaler \
  --wait --timeout 5m

# 기본 StorageClass. PVC에 storageClassName이 없으면 이것을 쓴다 (EKS가 만드는 gp2는 기본값이 아니고 암호화도 안 됨).
# reclaimPolicy Delete: PVC를 지우면 EBS 볼륨도 지워진다. WaitForFirstConsumer: Pod가 뜰 AZ에 볼륨을 만든다 (EBS는 AZ 하나에 묶임)
step "StorageClass gp3 (기본값, 암호화)"
kubectl apply -f - <<'YAML'
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gp3
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
  encrypted: "true"
reclaimPolicy: Delete
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
YAML

# 앱 네임스페이스. 앱·Secret·HTTPRoute·Ingress는 ArgoCD와 지은님이 넣는다.
#   osi7/gateway=true: Gateway(ecommerce-gateway)가 이 라벨이 있는 네임스페이스의 HTTPRoute만 받는다 (manifests/gateway.yaml)
#   pod-readiness-gate-inject: ALB(target-type ip) 대상이 healthy가 된 뒤에 이전 APISIX Pod를 내린다. Pod가 뜨기 전에 붙여야 적용된다
step "네임스페이스 ecommerce-main, ingress-apisix"
for ns in ecommerce-main ingress-apisix; do
  kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
done
kubectl label namespace ecommerce-main osi7/gateway=true --overwrite
kubectl label namespace ingress-apisix elbv2.k8s.aws/pod-readiness-gate-inject=enabled --overwrite

# EKS 액세스 정책(AmazonEKSAdminPolicy)에 없는 CRD 리소스(HTTPRoute, Rollout, ScaledObject, PluginConfig) 권한을 RBAC로 더한다
step "ArgoCD CRD 리소스 권한 (manifests/argocd-rbac.yaml)"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text | tr -d '\r')
sed "s|__ARGOCD_USER__|arn:aws:iam::$ACCOUNT_ID:user/osi7-argocd|" "$MANIFESTS/argocd-rbac.yaml" | kubectl apply -f -

# CRD는 차트에 들어 있는 파일을 그대로 쓴다 (온프렘도 --skip-crds로 설치하고 같은 파일로 CRD를 넣음). 크기가 커서 server-side apply
step "Gateway API·APISIX CRD (차트 $APISIX_CHART_VERSION 동봉)"
CHART_TMP=$(mktemp -d)
trap 'rm -rf "$CHART_TMP"' EXIT
helm pull apisix/apisix --version "$APISIX_CHART_VERSION" --untar -d "$CHART_TMP"
CRD_DIR="$CHART_TMP/apisix/charts/apisix-ingress-controller/crds"
kubectl apply --server-side -f "$CRD_DIR/gwapi-crds.yaml" -f "$CRD_DIR/apisixic-crds.yaml" >/dev/null
kubectl wait --for condition=established --timeout=60s crd/gateways.gateway.networking.k8s.io crd/gatewayproxies.apisix.apache.org

# admin key는 온프렘과 달라도 된다 (광렬님 확인). 이미 있으면 그대로 둔다 (다시 실행해도 키가 바뀌지 않게)
step "APISIX admin key (Secret ingress-apisix/apisix-admin-key)"
if kubectl -n ingress-apisix get secret apisix-admin-key >/dev/null 2>&1; then
  echo "이미 있음"
else
  kubectl -n ingress-apisix create secret generic apisix-admin-key \
    --from-literal=admin="$(openssl rand -hex 16)" --from-literal=viewer="$(openssl rand -hex 16)"
fi

# realIpFrom: ALB가 붙인 X-Forwarded-For는 VPC 안에서 온 것만 믿는다
VPC_CIDR=$(aws ec2 describe-vpcs --vpc-ids "$VPC_ID" --region "$REGION" --query 'Vpcs[0].CidrBlock' --output text | tr -d '\r')
# standalone 모드의 APISIX는 Ingress Controller가 설정을 넣어 줘야 ready(/status/ready 200)가 되고,
# Ingress Controller는 Gateway·GatewayProxy가 있어야 설정을 넣는다. 그래서 --wait 없이 설치하고 Gateway를 만든 뒤에 ready를 기다린다
# (--wait를 걸면 서로를 기다리다 시간 초과로 실패한다. 2026-10-26 발생)
step "APISIX $APISIX_CHART_VERSION (real IP 신뢰 대역 $VPC_CIDR)"
helm upgrade --install apisix apisix/apisix \
  --namespace ingress-apisix --version "$APISIX_CHART_VERSION" --skip-crds \
  -f "$MANIFESTS/apisix-values.yaml" \
  --set-json "apisix.nginx.http.realIpFrom=[\"$VPC_CIDR\"]"
kubectl -n ingress-apisix rollout status deploy/apisix-ingress-controller --timeout=5m

step "GatewayClass·GatewayProxy·Gateway (manifests/gateway.yaml)"
kubectl apply -f "$MANIFESTS/gateway.yaml"
kubectl -n ingress-apisix rollout status ds/apisix --timeout=5m
kubectl -n ingress-apisix wait --for=condition=Programmed gateway/ecommerce-gateway --timeout=2m

step "KEDA $KEDA_CHART_VERSION"
helm upgrade --install keda kedacore/keda \
  --namespace keda --create-namespace --version "$KEDA_CHART_VERSION" \
  --wait --timeout 5m

# Gateway API CRD가 먼저 있어야 한다 (Rollouts가 HTTPRoute 가중치를 바꿈)
step "Argo Rollouts $ROLLOUTS_CHART_VERSION"
helm upgrade --install argo-rollouts argo/argo-rollouts \
  --namespace argo-rollouts --create-namespace --version "$ROLLOUTS_CHART_VERSION" \
  -f "$MANIFESTS/argo-rollouts-values.yaml" \
  --wait --timeout 5m

# EKS에는 metrics-server가 기본으로 없다. HPA(CPU)와 KEDA cpu 트리거가 이 지표를 쓴다
step "metrics-server $METRICS_SERVER_VERSION"
kubectl apply -f "https://github.com/kubernetes-sigs/metrics-server/releases/download/$METRICS_SERVER_VERSION/components.yaml"
kubectl -n kube-system rollout status deploy/metrics-server --timeout=3m

status
echo
echo "완료. 다음: ArgoCD 담당(지은님)에게 알림(osi7-argocd로 엔드포인트·CA를 직접 조회해 클러스터 시크릿 갱신) -> 지은님 Secret 입력(ecommerce-main) -> ArgoCD로 앱·HTTPRoute·Ingress 배포 -> ALB 대상 healthy 확인(--status) -> terraform/dns에서 aws_ingress_enabled = true apply"
