#!/usr/bin/env bash
# 메인 apply 후 클러스터에 컨트롤러 2개를 Helm으로 설치한다 (Terraform은 IAM 역할과 Pod Identity 연결까지만 만든다).
#   - AWS Load Balancer Controller: Ingress를 보고 ALB를 만든다 (kube-system/aws-load-balancer-controller)
#   - Cluster Autoscaler: Pod가 Pending이면 노드 그룹을 min~max 안에서 늘린다 (kube-system/cluster-autoscaler)
# 기본 StorageClass gp3(암호화)도 만든다. EBS CSI 드라이버는 Terraform 애드온이고, PVC가 이 StorageClass로 EBS를 받는다 (2026-10-22 기준 AWS에서 PVC를 쓰는 앱은 없음).
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
REGION="${AWS_REGION:-ap-northeast-2}"

# winget으로 설치한 kubectl·helm이 Git Bash PATH에 없을 때를 대비한다
WINGET_LINKS="$HOME/AppData/Local/Microsoft/WinGet/Links"
[ -d "$WINGET_LINKS" ] && PATH="$PATH:$WINGET_LINKS"
for tool in aws terraform kubectl helm; do
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
helm repo update eks autoscaler >/dev/null

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

status
echo
echo "완료. 다음: 네임스페이스(ecommerce-main, ingress-apisix) 생성 -> ArgoCD 담당(지은님)에게 apply 완료 알림(osi7-argocd로 엔드포인트·CA를 직접 조회해 클러스터 시크릿 갱신) -> 예찬님 APISIX·Redis 설치 -> ArgoCD로 앱·Ingress 배포 -> ALB 생성 확인 -> terraform/dns에서 aws_ingress_enabled = true apply"
