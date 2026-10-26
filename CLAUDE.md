# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 개요

온프레미스 + AWS 하이브리드로 배포하는 마이크로서비스 쇼핑몰 앱의 AWS 쪽 인프라를 Terraform으로 관리한다 (프로젝트 `osi7`, 리전 `ap-northeast-2`). Terraform 코드는 모두 `terraform/`에 있고, 모든 명령은 이 폴더에서 실행한다. 코드 주석과 변수 description은 한국어로 쓰므로 새로 추가하는 것도 한국어로 맞춘다.

## 명령어

```bash
cd terraform
terraform init -backend-config=backend.hcl   # 처음 한 번. state는 S3에 있음
./scripts/check.sh           # fmt -check -> init -backend=false -> validate -> checkov -> infracost (AWS 자격 증명 불필요)
./scripts/check.sh --plan    # backend까지 init 후 plan, infracost는 plan JSON 기준 (checkov는 항상 코드 기준)
terraform fmt -recursive     # 포맷 자동 수정
checkov                      # 정적 보안 검사 (.checkov.yaml을 읽음)
infracost breakdown --config-file infracost.yml   # 비용 추산 (infracost-usage.yml의 사용량 가정 사용)
./scripts/install-controllers.sh   # 메인 apply 후 LB Controller·Cluster Autoscaler, gp3, 네임스페이스, APISIX·Gateway·KEDA·Argo Rollouts 설치 (--status는 상태와 내리기 전 ALB·PVC·EBS 확인)
./scripts/check-leftovers.sh       # 메인 destroy 후 남은 리소스 확인 (--fix는 확인을 받고 CNI ENI·EKS 클러스터 SG만 삭제)
```

`check.sh`는 설치되지 않은 도구를 실패로 처리하지 않고 건너뛰므로, 마지막 요약에서 건너뛴 항목을 확인한다.

### 원격 state

state는 S3 버킷(`osi7-tfstate-<계정ID>`)의 `aws/terraform.tfstate`에 있고, `use_lockfile`(S3 잠금 파일)로 동시 apply를 막는다. DynamoDB는 쓰지 않는다. `backend.tf`의 `backend "s3" {}`는 일부러 비워 두었고 (backend 블록에는 변수를 쓸 수 없음), 계정마다 다른 값은 `backend.hcl`에 있다.

버킷은 `terraform/bootstrap/`이 만든다. bootstrap은 별도의 Terraform 루트로, state를 로컬에 두고 계정마다 한 번만 apply한다. 버킷에는 `prevent_destroy`가 걸려 있다. 버킷 이름은 `terraform/backend.hcl`, `terraform/iam-users/backend.hcl`, `terraform/dns/backend.hcl`, `terraform/egress/backend.hcl`, `terraform/ecr/backend.hcl` 다섯 곳에 있다. bootstrap의 state(`terraform/bootstrap/terraform.tfstate`)는 git에 없고 bootstrap을 apply한 PC에만 있다. 다른 계정으로 옮길 때는 이 파일들의 `bucket`을 bootstrap 출력값 `state_bucket_name`으로 바꾸고 `terraform init -backend-config=backend.hcl -reconfigure`를 한다 (기존 state를 옮길 거라면 `-migrate-state`).

프로젝트 계정은 `918633123181`이다 (처음에는 테스트용이었고 그대로 프로젝트 계정으로 쓴다). 2026-10-21에 Free plan에서 **유료 플랜**으로 바꿨다 (남은 크레딧은 유지). Free plan 때는 프리 티어 대상 인스턴스 타입만 띄울 수 있어서 노드가 `m7i-flex.large`였다 (t3.small은 앱 Pod 메모리 요청에 부족). 유료 플랜 전환 후 같은 사양(2 vCPU / 8GiB)의 `m7i.large`로 바꿨다 (2026-10-22). flex는 기본 성능 40%에 "95% 시간 동안" 100%까지라 계속 높은 부하를 받는 부하 테스트에서 느려지는 구간이 생길 수 있고, m7i.large는 항상 100%다 (노드당 시간당 $0.1177 → $0.1239). t3는 CPU 크레딧 방식이라 부하 테스트에 맞지 않고, Graviton(m7g)은 이미지를 arm64로도 빌드해야 해서 쓰지 않는다. 더 큰 사양은 QA 결과를 보고 정한다. 타입을 바꾸면 노드 그룹이 새로 만들어지므로 (5~10분 중단) 메인이 내려가 있을 때 바꾼다. 대수는 평소 2대, 최대 4대다 (3대는 시스템 Pod를 빼면 앱용 약 4.0코어인데 앱 최대치가 3.8코어라 배치 여유가 없음. 노드는 Pending일 때만 늘어나 평소 비용은 같다). 유료 플랜은 크레딧을 다 쓰면 카드로 청구되므로 (Free plan처럼 계정이 닫히며 멈추지 않음) iam-users의 Budgets 알림으로 감시한다. 플랜 상태와 남은 크레딧은 `aws freetier get-account-plan-state`로 본다. 메인 인프라를 켜 두면 크레딧이 빨리 줄어드니 쓰지 않을 때는 destroy한다.

AWS 자격 증명: 루트와 테스트용 `sesac_cho`는 쓰지 않는다 (sesac_cho와 `sesac` 그룹은 삭제함). `aws login --profile myungho`로 로그인하고, Terraform과 CLI는 `AWS_PROFILE=terraform`(사용자 환경 변수로 설정됨)을 쓴다. `terraform` 프로필은 `credential_process`로 myungho의 로그인 세션을 읽는다. 그냥 `aws login`을 하면 `terraform` 프로필로 로그인을 시도해 실패하므로 `--profile myungho`를 꼭 붙인다. 계정 ID는 코드에 적지 않고 `aws_caller_identity`로 읽으므로, 계정마다 바뀌는 곳은 위의 `backend.hcl`들뿐이다.

### 새 계정에서 처음 적용하기

다른 계정으로 옮기게 될 때의 참고 절차다 (지금 계정은 이 순서로 이미 구성되어 있다). 루트 계정은 처음 관리자 한 명을 만드는 데만 쓰고, 나머지는 모두 `myungho`로 한다.

1. 루트로 콘솔에 로그인해 루트 MFA를 켠다. 루트 액세스 키는 만들지 않는다.
2. 콘솔에서 IAM 사용자 `myungho`를 직접 만들고 `AdministratorAccess`를 임시로 붙인다. 이후 작업은 `aws login --profile myungho`로 로그인해서 한다. Terraform은 `login_session`을 직접 읽지 못하므로, `~/.aws/config`에 `credential_process = aws configure export-credentials --profile myungho --format process`를 쓰는 프로필을 따로 만들어 `AWS_PROFILE`로 지정한다.
3. `terraform/bootstrap`에서 `terraform init` → `terraform apply`로 state 버킷을 만든다.
4. `terraform/backend.hcl`, `terraform/iam-users/backend.hcl`, `terraform/dns/backend.hcl`의 `bucket`을 새 버킷 이름으로 바꾼다. Route 53 영역도 새 계정에 만들고 가비아 네임서버를 바꾼다 (아래 "도메인").
5. `terraform/iam-users`에서 `terraform init -backend-config=backend.hcl -reconfigure` 후, 콘솔에서 만든 사용자를 가져온다: `terraform import 'aws_iam_user.this["myungho"]' myungho`. 그다음 apply하면 (`!` 프롬프트가 아니라 별도 터미널에서 해야 yes 확인을 입력할 수 있다) 그룹, 정책, 팀원이 만들어지고 `myungho`가 infra-admin 그룹에 들어간다.
6. 콘솔에서 `myungho`에 직접 붙였던 `AdministratorAccess`를 뗀다 (이제 그룹 권한을 받는다). 팀원 콘솔 비밀번호를 발급한다.
7. `terraform/`에서 `terraform init -backend-config=backend.hcl -reconfigure` 후 apply한다. 유료 플랜 계정이면 `eks_node_instance_types`를 실제 사양으로 바꾼다.

### 팀원 IAM (`terraform/iam-users/`)

팀원 IAM 사용자와 역할별 그룹(infra-admin, network, k8s-operator, cicd, observability, readonly, qa-k6, storage)은 별도 루트 `terraform/iam-users/`가 만든다. 같은 버킷의 `iam-users/terraform.tfstate`를 써서, 메인을 destroy해도 팀원 계정은 남는다. 그 폴더에서 `terraform init -backend-config=backend.hcl` 후 apply하고, 팀원은 `users` 변수(사용자 이름 -> 그룹 목록)로 관리한다. 권한은 그룹에만 붙이고, 모든 그룹에 자기 비밀번호·MFA·액세스 키 관리 정책(`self-mfa`)과 `aws login`용 AWS 관리형 정책 `SignInLocalDevelopmentAccess`가 붙는다 (없으면 `aws login`이 세션 선택 후 400 Bad Request로 실패한다. infra-admin은 AdministratorAccess에 포함되어 있어 드러나지 않았다). storage 그룹(준호)은 이름이 `osi7-product-`로 시작하는 버킷만 만들고 객체를 읽고 쓸 수 있다 (상품 이미지 테스트용. 버킷 정책·공개 차단·ACL 설정과 버킷 삭제는 없어서 공개로 바꿀 수 없고, state 버킷은 이름이 달라 건드릴 수 없다). 앱이 실제로 쓸 때는 앱 전용 권한(OCI 서비스 계정 키, AWS Pod Identity)을 따로 만든다. observability 그룹(홍섭)에는 콘솔 비용 조회용 `cost-read`(Cost Explorer·예산·크레딧·청구서 조회만, 결제 수단·변경 없음)가 붙는다. Cost Explorer API는 호출마다 $0.01이라 Grafana 역할에는 주지 않고, Grafana 비용 패널은 CloudWatch Billing 지표(`AWS/Billing`, us-east-1, 결제 기본 설정에서 켬)로 만든다. MFA 등록은 팀 규칙이고 정책으로 강제하지 않는다. `aws login`으로 받은 CLI 세션은 콘솔에서 MFA로 로그인했어도 `aws:MultiFactorAuthPresent=false`로 표시되므로, "MFA 없으면 Deny" 문을 넣으면 Terraform을 포함한 모든 CLI가 막힌다 (이 계정에서 확인). 콘솔 비밀번호와 액세스 키는 콘솔에서 발급한다. 루트 계정은 프로젝트에 쓰지 않고, Terraform은 `myungho`(infra-admin)로 실행한다. `myungho`는 처음에 콘솔에서 만들어 import한다 (위 "새 계정에서 처음 적용하기").

온프레미스 프로그램용 서비스 계정도 iam-users에 있다 (`local.service_users`, 팀원 그룹이 아니라서 self-mfa가 붙지 않음). `osi7-jenkins-ecr-push`는 같은 이미지를 Harbor와 ECR에 이중 push하고, `osi7-argocd`는 온프레미스 ArgoCD가 EKS를 원격 클러스터로 관리할 때 쓴다 (kubectl 권한은 메인의 Access Entry, `ecommerce-main`과 Ingress가 있는 `ingress-apisix` 네임스페이스만). ECR push 정책(`osi7-ecr-push`, `repository/<ecr_namespace>/*`)도 여기서 만들어 cicd 그룹과 Jenkins가 함께 쓴다. 메인에 두면 destroy 때마다 사용자와 키가 지워지기 때문이다. 액세스 키는 콘솔에서 발급해 CI/CD 담당에게 전달한다.

비용 알림(AWS Budgets, `budgets.tf`)도 메인 destroy와 상관없이 남도록 iam-users에 있다. 월 예산 `budget_limit_usd`(기본 $150)에 실제 사용 금액 단계 알림(`budget_actual_thresholds_usd`, 기본 $30/$80/$120)과 예상 금액 100% 알림을 건다. 크레딧을 빼기 전 금액 기준이다 (`include_credit = false`. 포함하면 크레딧이 남은 동안 늘 $0이라 알림이 오지 않는다). 받는 주소는 `iam-users/secret.auto.tfvars`의 `budget_alert_emails`이고, 비어 있으면 예산을 만들지 않는다.

`osi7-grafana`는 온프레미스 Grafana(mon-ubuntu)의 CloudWatch 데이터 소스용이다. AWS 밖이라 역할을 직접 붙일 수 없어서, 이 사용자의 키로는 조회 역할 `osi7-grafana-read`를 맡는 것(AssumeRole)만 하고 실제 조회는 역할의 임시 자격 증명으로 한다 (데이터 소스의 Assume Role ARN = `grafana_role_arn` 출력). 관측 담당이 CLI로 직접 볼 때는 본인 IAM 사용자로 `aws login`을 한다.

kubectl 권한은 메인의 `eks_access_entries`(같은 사용자 이름 -> EKS 액세스 정책, 네임스페이스)가 eks 모듈의 Access Entry로 만든다. EKS는 없는 IAM 사용자로 Access Entry를 만들 수 없으므로 iam-users를 먼저 apply한다. 클러스터 생성자 자동 관리자(`bootstrap_cluster_creator_admin_permissions`)는 꺼 두었으므로 클러스터 관리자도 이 변수에 명시한다.

### 도메인 (`terraform/dns/`)

가비아에서 산 `osi7.shop` 전체를 Route 53에 위임한다. **호스팅 영역은 Terraform 밖에서 콘솔로 만든다.** 영역을 다시 만들면 네임서버 4개가 바뀌어 가비아 등록과 위임 대기를 다시 해야 하므로, destroy로 지워질 일이 없게 했다. `terraform/dns`(별도 루트, `dns/terraform.tfstate`)는 그 영역을 `data "aws_route53_zone"`으로 이름으로 찾아 레코드와 IAM 권한만 관리한다. 영역이 없으면 plan이 실패한다. 같은 이름의 영역을 두 개 만들면 네임서버가 서로 달라지므로 영역은 하나만 만든다. 영역은 계정에 속하므로 다른 계정으로 옮기면 그 계정에 영역을 새로 만들고 가비아 네임서버를 다시 바꾼다 (`dns/backend.hcl`의 `bucket`도 계정에 맞게 바꾼다).

1. 콘솔 Route 53 → 호스팅 영역 생성 → `osi7.shop`, 퍼블릭 호스팅 영역.
2. 영역의 NS 레코드 값 4개를 가비아 도메인 관리의 **네임서버 설정**에 입력 (NS 레코드 추가가 아님, 끝의 `.`은 빼고).
3. `nslookup -type=NS osi7.shop`에 awsdns 주소 4개가 나오면 위임 완료.
4. `private_hosts`(호스트 이름 -> OCI private IP)에 넣고 `terraform/dns`에서 apply하면 `<호스트>.osi7.shop` A 레코드가 생긴다. 지금은 `harbor`(harbor-01 `10.0.1.94`)와 `grafana`(mon-01 `10.0.1.112`)다. OCI 이전 후 Tailscale은 쓰지 않으며, 사설 IP라 OCI VCN 안에서만 접속된다.

AWS 쪽 진입은 **ALB(Ingress) → APISIX**다. LB Controller가 Ingress를 보고 ALB를 만들고, TLS는 ALB에서 ACM 인증서로 끝낸 뒤 `target-type: ip`로 APISIX Pod(9080, `node_service_port_*`)에 바로 보낸다. NodePort는 쓰지 않는다. Ingress는 APISIX Service(`apisix-gateway`, Service 포트 80)와 같은 `ingress-apisix` 네임스페이스에 두고 backend에는 Service 포트 80을 적는다 (target-type ip라 ALB는 Pod 9080으로 바로 간다). ALB 대상 상태 검사는 APISIX 상태 엔드포인트(`alb_health_check_port` 7085, `/status/ready`, 200)를 쓴다 (annotation `healthcheck-port: "7085"`, `healthcheck-path: /status/ready`, `success-codes: "200"`). ALB에는 Terraform이 만든 `osi7-alb-sg`를 붙이고(annotation `alb.ingress.kubernetes.io/security-groups`), 노드 SG는 그 SG에서 오는 9080과 7085만 허용한다. LB Controller와 Cluster Autoscaler는 `scripts/install-controllers.sh`(Helm, 버전 고정, LB Controller에 `defaultTags.Project`)가 설치한다. ArgoCD는 `ecommerce-main`, `ingress-apisix` 네임스페이스 권한만 있어서 CRD와 클러스터 단위 리소스를 만들 수 없으므로, 앱 배포에 필요한 플랫폼도 같은 스크립트가 온프렘과 같은 버전·값(`scripts/manifests/`)으로 설치한다 (2026-10-26). 순서는 네임스페이스(`ecommerce-main`에 Gateway가 HTTPRoute를 받는 라벨 `osi7/gateway=true`, `ingress-apisix`에 ALB readiness gate 라벨) → Gateway API CRD v1.6.0 standard·APISIX CRD(차트 동봉 파일) → admin key Secret(새 임의 값, 이미 있으면 그대로) → APISIX 차트 2.18.2(standalone, etcd 없음, DaemonSet) → GatewayClass `apisix`·GatewayProxy·Gateway `ecommerce-gateway`(`manifests/gateway.yaml`) → KEDA 2.21.0 → Argo Rollouts 2.43.6(Gateway API 플러그인, 시작할 때 GitHub에서 받음)이다. 온프렘 values와 다른 점은 Service ClusterIP(NodePort 아님), real IP를 `X-Forwarded-For`로 VPC 대역에서만 믿기(IP 기준 rate-limit이 ALB IP에 걸리지 않게), Gateway 리스너가 http 하나(TLS는 ALB에서 끝나고 cert-manager 인증서가 없음)인 것뿐이다. 버전을 바꿀 때는 온프렘과 같이 바꾼다. 앱·Secret·HTTPRoute·Ingress는 OCI ArgoCD와 지은님이 배포한다. 내릴 때는 dns `aws_ingress_enabled = false` apply → ArgoCD 앱 삭제(또는 sync 끄기) → Ingress 삭제 → ALB 삭제 확인 → (PVC가 있으면) PVC 삭제 → EBS 삭제 확인 → 메인 destroy 순서다. 쿠폰은 온프레미스에서만 처리해서 AWS에는 `redis-coupon`이 없고, AWS의 Redis는 디스크 없는 `redis-cache`뿐이라 지금은 PVC가 없다. ALB와 PVC의 EBS 볼륨은 Terraform state에 없어서 destroy가 지우지 않고, LB Controller와 EBS CSI 드라이버가 살아 있을 때 지워야 같이 없어진다 (StatefulSet을 지워도 PVC는 남는다). 남은 ALB·PVC·EBS 개수는 `install-controllers.sh --status`의 마지막 항목으로 본다. destroy 뒤에는 `scripts/check-leftovers.sh`로 남은 것이 없는지 확인한다. 노드가 먼저 종료되면 VPC CNI가 추가로 붙인 ENI(`aws-K8S-i-...`)가 정리되지 않고 남아 서브넷·노드 SG를 붙잡고, 그 때문에 EKS 클러스터 SG(`eks-cluster-sg-osi7-eks-*`)도 남아 VPC 삭제가 실패할 수 있다 (2026-10-22 발생). 그때는 `check-leftovers.sh --fix`로 둘을 지우고 destroy를 다시 실행한다. 그 인증서(`shop`, `api`, `acm_hosts` 변수)는 메인 destroy와 상관없이 남도록 `terraform/dns`가 DNS 검증으로 만들고, ARN은 `acm_certificate_arn` 출력이다 (annotation `alb.ingress.kubernetes.io/certificate-arn`).

`acm_hosts`(shop, api)는 온프레미스와 AWS가 같이 받는 이름이라, `terraform/dns`가 쪽마다 가중치 레코드를 하나씩 만든다 (`set_identifier` onprem / aws).
- **온프레미스 쪽:** `onprem_public_ip`(OCI edge-proxy `132.145.89.131`)를 가리키는 A 레코드다 (TTL 60). 이 IP가 비어 있으면 온프레미스 레코드와 `onprem_hosts`(온프레미스 전용 단순 A 레코드)를 만들지 않는다. `onprem_hosts`는 keycloak과 OCI 개발 환경 와일드카드 `*.dev`(`shop.dev`, `api.dev`, `keycloak.dev` 등)다 (web이 화면 주소 맨 앞을 `api`로 바꿔 API 주소를 정하므로 개발용도 `shop.dev` / `api.dev`처럼 같은 단계로 맞춘다).
- **AWS 쪽:** LB Controller가 만든 LB를 `aws_lb_tags`로 찾아 가리키는 alias 레코드다 (`evaluate_target_health`).
- **AWS 쪽 켜고 끄는 순서:** 메인 apply → LB 생성 → `aws_ingress_enabled = true`로 dns apply. 메인을 destroy하기 **전에** false로 apply한다. 켜 둔 채로 LB가 없어지면 dns plan이 조회 실패로 멈춘다.
- **전환 단계:** QA 단계는 온프레미스:AWS = 100:0 → 80:20 → 50:50 → 20:80 → 0:100 → 롤백 100:0이다. 단계마다 `terraform/dns/weights/<온프레미스>-<AWS>.tfvars` 파일이 있어 `terraform apply -var-file=weights/50-50.tfvars`처럼 apply한다 (`aws_ingress_enabled = true` 포함. 롤백은 `100-0`). 가중치는 질의마다 적용되고 리졸버가 응답을 TTL 동안 캐시하므로, 클라이언트 한 대에서 재면 1분 단위로 한쪽에 몰린다. AWS 쪽은 ALB alias라 TTL을 정할 수 없고(60초 고정), 온프레미스 쪽만 낮추면 비율이 AWS로 치우치므로 TTL은 양쪽 모두 60초로 둔다.
- **상태 검사:** `onprem_health_check_path`(`/healthz`)를 넣으면 온프레미스 쪽에 Route 53 HTTPS 상태 검사가 붙는다 (개당 월 약 $2.75). OCI 앱이 `/healthz`에 200을 주기 전에는 비워 둔다. 간격은 `onprem_health_check_interval`(30 또는 10초, 10초는 약 $2 추가, 바꾸면 상태 검사를 새로 만듦), 실패 횟수는 `onprem_health_check_failure_threshold`(기본 3)다. Route 53 검사기는 인터넷에서 들어오므로 edge-proxy 443이 열려 있어야 한다. ALB 이름과 CloudWatch 차원 값은 `aws_lb_name`, `aws_lb_arn_suffix` 출력이다.

Harbor 인증서(Let's Encrypt, DNS-01)는 첫 발급만 수동이다. 온프레미스 담당이 알려 주는 `_acme-challenge.harbor` TXT를 콘솔에서 넣고, 발급 후 지운다 (Terraform 코드에 없는 레코드라 apply가 건드리지 않는다). 그다음 `create_acme_user = true`로 apply해 자동 갱신용 사용자 `osi7-acme-harbor`를 만들고, 콘솔에서 액세스 키를 발급해 영역 ID(`zone_id` 출력)와 함께 전달한다. 이 사용자는 `acme_hosts`(harbor, shop, api, keycloak, grafana, dev, `*.dev` — 온프레미스 쪽 인증서. dev는 `*.dev.osi7.shop` 와일드카드 인증서의 TXT 이름, `*.dev`는 `keycloak.dev` 같은 개발 호스트별 인증서)로 정한 `_acme-challenge.<호스트>.osi7.shop` TXT만 바꿀 수 있다 (조건이 StringLike라 `*`를 쓸 수 있다. 운영 이름은 하나씩 적어서 새 운영 이름의 인증서는 받을 수 없게 한다). 이름은 harbor지만 사용자를 다시 만들면 발급한 키가 무효가 되므로 이름은 그대로 둔다. 인증서는 90일짜리이고 만료 30일 전에 갱신되므로, 첫 발급 후 60일 안에 자동화를 끝낸다.

### 온프레미스 연결 (`terraform/egress/`, NAT + edge-proxy)

AWS와 OCI는 네트워크로 잇지 않는다 (VPN 없음). EKS의 앱은 NAT Gateway로 인터넷에 나가 OCI edge-proxy(`132.145.89.131`)의 TCP 프록시로 들어가고, edge-proxy가 OCI 안의 대상(DB NLB 등)으로 넘긴다. AWS가 닿을 수 있는 곳은 edge-proxy가 열어 둔 포트뿐이다.

- **고정 NAT IP:** OCI 보안 목록은 AWS NAT 공인 IP/32만 허용한다. NAT의 EIP를 메인에서 만들면 apply할 때마다 IP가 바뀌므로, EIP는 별도 루트 `terraform/egress/`(`egress/terraform.tfstate`)가 만들고 **프로젝트가 끝날 때까지 지우지 않는다** (`prevent_destroy`). 공인 IPv4는 붙어 있지 않아도 시간당 $0.005(월 약 $3.6)가 나간다. IP는 `terraform/egress`의 출력 `nat_public_ips`로 보고 네트워크 담당에게 전달한다.
- **메인:** `data "aws_eip"`로 Name 태그 `osi7-egress-eip-<번호>`를 찾아 network 모듈의 `nat_eip_allocation_ids`로 넘긴다 (비우면 모듈이 EIP를 직접 만든다. `docs/cli` 비교용 기본 동작). egress의 `nat_eip_count`는 메인 `nat_gateway_count`와 같게 둔다. egress 루트가 없으면 메인 plan이 EIP 조회 실패로 멈추므로, apply 순서는 iam-users -> dns -> egress -> 메인이다.
- **인터넷을 지나므로** DB 연결은 MySQL TLS를 쓴다 (DB 담당). edge-proxy는 L4 프록시라 TLS를 풀지 않는다.
- **OCI 쪽(네트워크 담당):** edge-proxy의 TCP 프록시(포트 -> 대상), public 보안 목록에 AWS NAT IP/32 -> 그 포트. DB에는 출발지가 edge-proxy로 보이므로 DB 쪽에 AWS 대역을 열 필요는 없다.
- **ArgoCD -> EKS:** 반대 방향도 VPN 없이 EKS public endpoint로 간다. `eks_public_access_cidrs`에 OCI private 서브넷 NAT Gateway 공인 IP `140.238.24.33/32`를 넣었다 (cp-01, wk-01/02가 이 IP로 나감). 팀원 PC에서 kubectl을 쓰려면 그 공인 IP/32도 추가한다. 학원 IP처럼 git에 남기지 않을 값은 `terraform/local.auto.tfvars`(gitignore, 자동으로 읽힘)에 OCI NAT IP와 함께 목록 전체를 적는다 (목록 변수는 합쳐지지 않고 덮어쓰며, `*.auto.tfvars`는 이름 순서로 읽혀 뒤 파일이 이긴다. 그래서 `secret.auto.tfvars`에는 이 변수를 넣지 않는다).
- Site-to-Site VPN(`terraform/vpn/`)은 이 방식으로 바꾸면서 2026-10-19에 destroy하고 폴더를 지웠다.

### ECR (`terraform/ecr/`)

ECR 리포지토리는 별도 루트 `terraform/ecr/`(`ecr/terraform.tfstate`)가 `modules/ecr`로 만든다. 메인에 두면 테스트 후 destroy할 때마다 Jenkins가 push한 이미지가 지워지기 때문이다 (2026-10-20 메인에서 옮김. 메인에는 `removed`(destroy = false) 블록, 이쪽에는 `import` 블록이 있고, 리포지토리를 추가하기 전에 `import` 블록을 지운다). `force_delete = false`라 이미지가 남은 리포지토리는 destroy가 거부된다. 비용은 저장 용량(GB당 월 $0.10)뿐이다. 레지스트리 주소와 이미지 경로는 이 루트의 출력 `registry_url`, `repository_urls`다. 메인은 이 state를 읽지 않으므로 apply 순서와 상관없다.

## 구조

루트 `main.tf`가 `terraform/modules/` 아래 모듈 4개(network, security, iam, eks)를 연결한다 (ecr 모듈은 `terraform/ecr`이 쓴다). 모듈 사이의 값은 모듈 출력으로만 주고받는다.

- **network**: VPC와 2계층 × AZ 2개 서브넷 (public / private app). DB 서브넷은 없다 (DB는 온프레미스에서만 운영, 아래 참고). public·app 서브넷에는 AWS Load Balancer Controller가 쓰는 `kubernetes.io/role/(internal-)elb` 태그가 붙어 있다. NAT 개수는 `nat_gateway_count`(1 또는 2)로 정하고, EIP는 `terraform/egress`의 고정 EIP를 받는다 (위 "온프레미스 연결"). app 라우트 테이블은 `min(index, count-1)`로 NAT를 고르므로, NAT가 1개면 두 AZ가 같은 NAT를 쓴다.
- **security**: ALB / 노드 보안 그룹. ALB SG와 노드 SG가 서로를 참조하므로, 인라인 규칙 대신 `aws_vpc_security_group_*_rule` 리소스로 규칙을 따로 붙인다 (인라인으로 쓰면 순환 참조가 생긴다). ALB SG는 인터넷 80/443을 받아 노드 SG의 APISIX 포트(9080)와 상태 검사 포트(7085)로만 보낸다. 온프레미스 관련 규칙은 없다 (DB는 노드 아웃바운드 전체 허용으로 나감). 노드로 들어오는 온프레미스 규칙(SSH, 6443)은 일부러 두지 않았다. K8s API는 EKS 컨트롤 플레인에 있고, 노드 접속은 SSM으로 한다.
- **ecr** (`terraform/ecr`이 사용): `repositories`의 이름마다 `<namespace>/<이름>` 리포지토리를 만든다. 지금은 `ecommerce/` + auth, product, order, promotion, web이다. namespace는 온프레미스 Harbor 프로젝트 이름과 같게 둔다. 정책은 만들지 않는다. 노드 pull 정책은 iam 모듈, push 정책은 iam-users에 있다 (같은 이름의 정책을 두 곳에서 만들면 apply가 실패한다).
- **iam**: 노드 역할(EKS worker + CNI + 프로젝트 ECR pull + AWS 관리형 `AmazonEC2ContainerRegistryPullOnly`)과 EKS 클러스터 역할을 만든다. 프로젝트 ECR pull 정책(`osi7-ecr-pull`)은 `terraform/ecr`의 state를 읽지 않도록 `repository/<ecr_namespace>/*` 범위로 여기서 만든다. Jenkins·ArgoCD·Grafana 사용자는 iam-users에 있다.
- **eks**: app 서브넷에 클러스터를 만든다. Secrets는 KMS로 암호화하고, 컨트롤 플레인 로그는 모든 종류를 남기며, 인증 모드는 `API_AND_CONFIG_MAP`이다. 공개 엔드포인트는 `eks_public_access_cidrs`가 비어 있지 않을 때만 켜진다. 관리형 노드 그룹은 시작 템플릿으로 IMDSv2와 hop limit 1을 강제해 파드가 노드 권한을 쓰지 못하게 한다 (파드 권한은 Pod Identity/IRSA로 부여). EBS는 암호화된 gp3를 쓴다. PVC용 EBS CSI 드라이버는 애드온(`aws-ebs-csi-driver`, Pod Identity 역할 `osi7-ebs-csi-driver`)이고, 드라이버가 만드는 볼륨에도 provider 기본 태그가 붙는다 (`extraVolumeTags`). 기본 StorageClass `gp3`(암호화, `reclaimPolicy: Delete`, `WaitForFirstConsumer`)는 `install-controllers.sh`가 만든다. 쿠폰 Redis용으로 추가했지만 쿠폰 발급 경로(`/promotion/storefront/promotions`)는 항상 온프레미스로 보내 수량 기준을 한 곳에 두기로 해서(2026-10-22), 지금 AWS에서 PVC를 쓰는 앱은 없다 (비용이 없어 남겨 둠). PVC를 쓰게 되면 EBS가 AZ 하나에 묶이고 노드 그룹 하나가 두 AZ에 걸쳐 있어서 CA가 그 AZ에 노드를 늘린다는 보장이 없다는 점을 고려한다 (평소 AZ마다 노드가 1대씩 있고, 꽉 찰 때를 대비해 PriorityClass를 준다). 노드 그룹은 `desired_size` 변경을 무시하고, 애드온은 노드 그룹이 생긴 뒤에 설치한다. 팀원 kubectl 권한은 `access_entries`로 Access Entry와 액세스 정책을 붙인다 (namespaces가 비면 클러스터 전체. `extra_policies`(정책 -> 네임스페이스)로 특정 네임스페이스에만 정책을 더 줄 수 있다. QA는 전체 View만 받는다. 부하 테스트는 앱과 노드 자원을 나눠 쓰지 않도록 클러스터 밖에서 하므로, 측정용 `qa` 네임스페이스 Edit은 2026-10-22에 뺐다). 노드 인스턴스와 EBS에는 시작 템플릿의 `tag_specifications`로 provider 기본 태그(`Project` 등)를 직접 넣는다 (default_tags는 시작 템플릿 자체에만 붙고 뜨는 인스턴스에는 전달되지 않아, 없으면 비용 할당 태그로 노드 비용이 잡히지 않는다). AWS Load Balancer Controller의 역할(`osi7-aws-load-balancer-controller`, 공식 정책 파일 `modules/eks/policies/`에 버전 고정)과 `kube-system/aws-load-balancer-controller` Pod Identity 연결도 만든다. 컨트롤러 설치(Helm)는 Terraform 밖이고, 설치 버전을 올리면 정책 파일도 같은 버전으로 바꾼다. Cluster Autoscaler도 역할(`osi7-cluster-autoscaler`)과 `kube-system/cluster-autoscaler` Pod Identity 연결만 만든다 (설치는 Helm, `autoDiscovery.clusterName`). 개수 변경·종료는 EKS가 관리형 노드 그룹 ASG에 자동으로 붙이는 `k8s.io/cluster-autoscaler/<클러스터> = owned` 태그 조건으로 제한하고, 노드 수는 `eks_node_min_size`~`max_size` 안에서만 바뀐다. 노드·Pod 지표와 컨테이너 로그는 `amazon-cloudwatch-observability` 애드온(Container Insights, Pod Identity 역할 `osi7-cloudwatch-agent`)이 CloudWatch로 보내고, 온프레미스 Grafana가 CloudWatch에서 조회한다 (Prometheus remote_write, Loki 직접 전송은 쓰지 않음). 애드온 기본값은 모든 Pod에 OpenTelemetry 에이전트(Application Signals)를 넣으므로 `monitorAllServices = false`로 끈다 (앱에 Java 에이전트가 붙어 온프렘과 성능 비교가 달라지고 트레이스 요금이 생김, 2026-10-26). 앱 지표는 `eks_app_metrics_enabled`(기본 false)를 켜면 같은 에이전트가 `ecommerce-main` Pod의 9000 `/actuator/prometheus`를 60초마다 긁어 EMF로 CloudWatch 네임스페이스 `osi7/App`에 보낸다 (HTTP 요청 수·처리 시간 합계는 디멘션 `ClusterName, Namespace, Service, StatusClass`, HikariCP는 `ClusterName, Namespace, Service`). `agent.config`를 넣으면 애드온 기본 설정이 통째로 바뀌므로 기본 설정(kubernetes, application_signals)을 같이 적고, 노드마다 뜨는 에이전트가 같은 Pod를 중복 수집하지 않게 target allocator를 켠다. 사용자 지정 지표는 조합마다 월 $0.30(보내는 시간만큼)이라 Pod 이름·URI는 디멘션에 넣지 않고, 앱이 떠 있을 때만 켠다. EMF 로그 그룹 `prometheus`도 30일 보관으로 Terraform이 만든다. 로그 그룹 `/aws/containerinsights/<클러스터>/*`는 보관 30일로 Terraform이 먼저 만든다 (에이전트가 만들면 무기한 보관이고 destroy해도 남음).

**DB는 온프레미스에서만 운영한다** (MySQL 8.4, GTID). AWS에는 RDS도, 클라우드 백업·복제도 두지 않는다. 그래서 EKS의 서비스는 온프레미스 연결을 통해 온프레미스 DB(OCI db-01~03)에 접속하며 (AWS 앱의 접속 주소는 `132.145.89.131:6450`. NAT -> edge-proxy TCP 프록시 6450 -> OCI 내부 NLB `10.0.1.111:6450` -> MySQL Router. 앱 설정 값이라 Terraform에는 없다), 이 연결이 끊기면 AWS 쪽 앱도 DB를 쓸 수 없다. 노드 SG의 아웃바운드는 이미 전체 허용이라 SG 변경은 필요 없다.

온프레미스는 학원 PC(VirtualBox, 이중 NAT라 공인 진입 불가)에서 OCI(ap-seoul-1, VCN `demovcn` 10.0.0.0/16)로 전체 이전했다. 공인 IP는 배스천 겸 외부 진입점인 edge-proxy(`132.145.89.131`, 고정 IP, 사설 10.0.0.47) 하나뿐이고, 나머지 VM은 private 10.0.1.0/24에 있다. AWS와는 네트워크로 잇지 않고 edge-proxy의 TCP 프록시로만 통신한다 (위 "온프레미스 연결"). keycloak은 공인 `keycloak.osi7.shop`으로 접속한다. EKS Service 대역은 온프레미스(Pod 10.233.64.0/18, Service 10.233.0.0/18)와 겹치지 않게 `eks_service_cidr`(172.20.0.0/16)로 고정했다 (클러스터 생성 후 변경 불가).

`docs/cli/`는 멘토 권장 순서(콘솔 → CLI → 정리 → Terraform)의 기록이다. network·security·ECR 1개(`ecommerce-cli/web`. `ecommerce/web`은 `terraform/ecr`에 늘 있어서 이름만 다르게)·노드 IAM 역할을 Terraform과 같은 이름으로 CLI 스크립트(`01`~`04`, `99-cleanup.sh`)로 만들고 지운 뒤, `snapshot.sh`로 CLI 결과와 Terraform 결과를 ID 없이 비교한다 (QA A-IAC-01). CLI로 만든 것은 `ManagedBy=cli` 태그로 구분한다. CLI 리소스와 메인 Terraform을 동시에 올리면 같은 이름의 VPC가 두 개 생기므로, 반드시 정리한 뒤 apply한다. Terraform 모듈의 이름·규칙을 바꾸면 이 스크립트도 같이 맞춘다.

## 규칙

- 루트 변수는 `variables.tf`에 기본값과 함께 선언하고, 같은 값을 `terraform.tfvars`에도 적는다 (`terraform.tfvars`는 팀 엑셀 '변수' 시트와 대응). 값은 `terraform.tfvars`에서 수정하고, 변수를 추가할 때는 기본값도 함께 맞춘다. 노드 서비스 포트 범위, 노드 인스턴스 타입 등은 팀원 확인을 기다리는 임시값이다.
- 비밀 값은 `secret.auto.tfvars`에 넣는다 (gitignore 대상).
- Checkov 예외는 `.checkov.yaml`이 아니라 해당 리소스 옆에 `#checkov:skip=CKV_...:<사유>` 주석으로 남기고, 사유를 꼭 적는다.
- 4주짜리 학습 프로젝트라서 비용을 아끼는 설정들은 의도한 것이며, 그 이유는 skip 주석에 적혀 있다. VPC Flow Logs 미사용, 로그 30일 보관, NAT 1개가 해당한다.
