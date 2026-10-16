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
```

`check.sh`는 설치되지 않은 도구를 실패로 처리하지 않고 건너뛰므로, 마지막 요약에서 건너뛴 항목을 확인한다.

### 원격 state

state는 S3 버킷(`osi7-tfstate-<계정ID>`)의 `aws/terraform.tfstate`에 있고, `use_lockfile`(S3 잠금 파일)로 동시 apply를 막는다. DynamoDB는 쓰지 않는다. `backend.tf`의 `backend "s3" {}`는 일부러 비워 두었고 (backend 블록에는 변수를 쓸 수 없음), 계정마다 다른 값은 `backend.hcl`에 있다.

버킷은 `terraform/bootstrap/`이 만든다. bootstrap은 별도의 Terraform 루트로, state를 로컬에 두고 계정마다 한 번만 apply한다. 버킷에는 `prevent_destroy`가 걸려 있다. 버킷 이름은 `terraform/backend.hcl`, `terraform/iam-users/backend.hcl`, `terraform/dns/backend.hcl` 세 곳에 있다. bootstrap의 state(`terraform/bootstrap/terraform.tfstate`)는 git에 없고 bootstrap을 apply한 PC에만 있다. 다른 계정으로 옮길 때는 세 파일의 `bucket`을 bootstrap 출력값 `state_bucket_name`으로 바꾸고 `terraform init -backend-config=backend.hcl -reconfigure`를 한다 (기존 state를 옮길 거라면 `-migrate-state`).

프로젝트 계정은 `918633123181`이다 (처음에는 테스트용이었고 그대로 프로젝트 계정으로 쓴다). 지금은 **Free plan**이라 프리 티어 대상 인스턴스 타입만 띄울 수 있고(그래서 노드가 `m7i-flex.large` 2~3대. t3.small은 앱 Pod 메모리 요청에 부족), 크레딧이 떨어지거나 플랜 만료일이 지나면 계정이 닫힌다. 유료 플랜으로 바꿀 예정이며, 바꾸면 `eks_node_instance_types`를 실제 사양으로 올린다. 플랜 상태와 남은 크레딧은 `aws freetier get-account-plan-state`로 본다. 메인 인프라를 켜 두면 크레딧이 빨리 줄어드니 쓰지 않을 때는 destroy한다.

AWS 자격 증명: 루트와 테스트용 `sesac_cho`는 쓰지 않는다 (sesac_cho와 `sesac` 그룹은 삭제함). `aws login --profile myungho`로 로그인하고, Terraform과 CLI는 `AWS_PROFILE=terraform`(사용자 환경 변수로 설정됨)을 쓴다. `terraform` 프로필은 `credential_process`로 myungho의 로그인 세션을 읽는다. 그냥 `aws login`을 하면 `terraform` 프로필로 로그인을 시도해 실패하므로 `--profile myungho`를 꼭 붙인다. 계정 ID는 코드에 적지 않고 `aws_caller_identity`로 읽으므로, 계정마다 바뀌는 곳은 위의 `backend.hcl` 세 개뿐이다.

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

팀원 IAM 사용자와 역할별 그룹(infra-admin, network, k8s-operator, cicd, observability, readonly, qa-k6)은 별도 루트 `terraform/iam-users/`가 만든다. 같은 버킷의 `iam-users/terraform.tfstate`를 써서, 메인을 destroy해도 팀원 계정은 남는다. 그 폴더에서 `terraform init -backend-config=backend.hcl` 후 apply하고, 팀원은 `users` 변수(사용자 이름 -> 그룹 목록)로 관리한다. 권한은 그룹에만 붙이고, 모든 그룹에 자기 비밀번호·MFA·액세스 키 관리 정책(`self-mfa`)이 붙는다. MFA 등록은 팀 규칙이고 정책으로 강제하지 않는다. `aws login`으로 받은 CLI 세션은 콘솔에서 MFA로 로그인했어도 `aws:MultiFactorAuthPresent=false`로 표시되므로, "MFA 없으면 Deny" 문을 넣으면 Terraform을 포함한 모든 CLI가 막힌다 (이 계정에서 확인). 콘솔 비밀번호와 액세스 키는 콘솔에서 발급한다. 루트 계정은 프로젝트에 쓰지 않고, Terraform은 `myungho`(infra-admin)로 실행한다. `myungho`는 처음에 콘솔에서 만들어 import한다 (위 "새 계정에서 처음 적용하기").

온프레미스 프로그램용 서비스 계정도 iam-users에 있다 (`local.service_users`, 팀원 그룹이 아니라서 self-mfa가 붙지 않음). `osi7-jenkins-ecr-push`는 같은 이미지를 Harbor와 ECR에 이중 push하고, `osi7-argocd`는 온프레미스 ArgoCD가 EKS를 원격 클러스터로 관리할 때 쓴다 (kubectl 권한은 메인의 Access Entry, `ecommerce-main` 네임스페이스만). ECR push 정책(`osi7-ecr-push`, `repository/<ecr_namespace>/*`)도 여기서 만들어 cicd 그룹과 Jenkins가 함께 쓴다. 메인에 두면 destroy 때마다 사용자와 키가 지워지기 때문이다. 액세스 키는 콘솔에서 발급해 CI/CD 담당에게 전달한다.

kubectl 권한은 메인의 `eks_access_entries`(같은 사용자 이름 -> EKS 액세스 정책, 네임스페이스)가 eks 모듈의 Access Entry로 만든다. EKS는 없는 IAM 사용자로 Access Entry를 만들 수 없으므로 iam-users를 먼저 apply한다. 클러스터 생성자 자동 관리자(`bootstrap_cluster_creator_admin_permissions`)는 꺼 두었으므로 클러스터 관리자도 이 변수에 명시한다.

### 도메인 (`terraform/dns/`)

가비아에서 산 `osi7.shop` 전체를 Route 53에 위임한다. **호스팅 영역은 Terraform 밖에서 콘솔로 만든다.** 영역을 다시 만들면 네임서버 4개가 바뀌어 가비아 등록과 위임 대기를 다시 해야 하므로, destroy로 지워질 일이 없게 했다. `terraform/dns`(별도 루트, `dns/terraform.tfstate`)는 그 영역을 `data "aws_route53_zone"`으로 이름으로 찾아 레코드와 IAM 권한만 관리한다. 영역이 없으면 plan이 실패한다. 같은 이름의 영역을 두 개 만들면 네임서버가 서로 달라지므로 영역은 하나만 만든다. 영역은 계정에 속하므로 다른 계정으로 옮기면 그 계정에 영역을 새로 만들고 가비아 네임서버를 다시 바꾼다 (`dns/backend.hcl`의 `bucket`도 계정에 맞게 바꾼다).

1. 콘솔 Route 53 → 호스팅 영역 생성 → `osi7.shop`, 퍼블릭 호스팅 영역.
2. 영역의 NS 레코드 값 4개를 가비아 도메인 관리의 **네임서버 설정**에 입력 (NS 레코드 추가가 아님, 끝의 `.`은 빼고).
3. `nslookup -type=NS osi7.shop`에 awsdns 주소 4개가 나오면 위임 완료.
4. `harbor_ip`(harbor-01의 Tailscale IP)를 넣고 `terraform/dns`에서 apply하면 `harbor.osi7.shop` A 레코드가 생긴다. Tailscale IP라 tailnet 안의 기기(Jenkins, 온프레미스 K8s 노드)에서만 접속된다.

AWS 쪽 진입은 Gateway API 컨트롤러 앞에 LB Controller가 만든 NLB를 두고, TLS는 NLB에서 ACM 인증서로 끝낸다. 그 인증서(`shop`, `api`, `acm_hosts` 변수)는 메인 destroy와 상관없이 남도록 `terraform/dns`가 DNS 검증으로 만들고, ARN은 `acm_certificate_arn` 출력이다. (진입 방식은 NLB → Gateway와 ALB → APISIX 중 아직 미정)

`acm_hosts`(shop, api)는 온프레미스와 AWS가 같이 받는 이름이라, `terraform/dns`가 쪽마다 가중치 레코드를 하나씩 만든다 (`set_identifier` onprem / aws).
- **온프레미스 쪽:** `onprem_public_ip`를 가리키는 A 레코드다 (TTL 60). 이 IP가 비어 있으면 온프레미스 레코드와 `onprem_hosts`(keycloak, 온프레미스 전용 단순 A 레코드)를 만들지 않는다.
- **AWS 쪽:** LB Controller가 만든 LB를 `aws_lb_tags`로 찾아 가리키는 alias 레코드다 (`evaluate_target_health`).
- **AWS 쪽 켜고 끄는 순서:** 메인 apply → LB 생성 → `aws_ingress_enabled = true`로 dns apply. 메인을 destroy하기 **전에** false로 apply한다. 켜 둔 채로 LB가 없어지면 dns plan이 조회 실패로 멈춘다.
- **전환 단계:** 온프레미스:AWS = 100:0 → 95:5 → 50:50 → 0:100이다. `onprem_weight`와 `aws_weight`만 바꿔 dns를 apply한다.
- **상태 검사:** `onprem_health_check_path`를 넣으면 온프레미스 쪽에 Route 53 HTTPS 상태 검사가 붙는다 (개당 월 약 $2.75).

Harbor 인증서(Let's Encrypt, DNS-01)는 첫 발급만 수동이다. 온프레미스 담당이 알려 주는 `_acme-challenge.harbor` TXT를 콘솔에서 넣고, 발급 후 지운다 (Terraform 코드에 없는 레코드라 apply가 건드리지 않는다). 그다음 `create_acme_user = true`로 apply해 자동 갱신용 사용자 `osi7-acme-harbor`를 만들고, 콘솔에서 액세스 키를 발급해 영역 ID(`zone_id` 출력)와 함께 전달한다. 이 사용자는 `acme_hosts`(harbor, shop, api, keycloak — 온프레미스 쪽 인증서)로 정한 `_acme-challenge.<호스트>.osi7.shop` TXT만 바꿀 수 있다. 이름은 harbor지만 사용자를 다시 만들면 발급한 키가 무효가 되므로 이름은 그대로 둔다. 인증서는 90일짜리이고 만료 30일 전에 갱신되므로, 첫 발급 후 60일 안에 자동화를 끝낸다.

## 구조

루트 `main.tf`가 `terraform/modules/` 아래 모듈 5개를 연결한다. 모듈 사이의 값은 모듈 출력으로만 주고받는다.

- **network**: VPC와 2계층 × AZ 2개 서브넷 (public / private app). DB 서브넷은 없다 (DB는 온프레미스에서만 운영, 아래 참고). public·app 서브넷에는 AWS Load Balancer Controller가 쓰는 `kubernetes.io/role/(internal-)elb` 태그가 붙어 있다. NAT 개수는 `nat_gateway_count`(1 또는 2)로 정한다. app 라우트 테이블은 `min(index, count-1)`로 NAT를 고르므로, NAT가 1개면 두 AZ가 같은 NAT를 쓴다.
- **security**: ALB / 노드 보안 그룹. ALB SG와 노드 SG가 서로를 참조하므로, 인라인 규칙 대신 `aws_vpc_security_group_*_rule` 리소스로 규칙을 따로 붙인다 (인라인으로 쓰면 순환 참조가 생긴다). 온프레미스 관련 규칙은 아직 없다 (연결 방식이 정해지면 추가). 노드로 들어오는 온프레미스 규칙(SSH, 6443)은 일부러 두지 않았다. K8s API는 EKS 컨트롤 플레인에 있고, 노드 접속은 SSM으로 한다.
- **ecr**: `ecr_repositories`의 이름마다 `<ecr_namespace>/<이름>` 리포지토리를 만든다. 지금은 `ecommerce/` + auth, product, order, promotion, web이다. namespace는 온프레미스 Harbor 프로젝트 이름과 같게 둔다. 노드가 쓰는 pull 정책은 이 모듈에서 만들고, push 정책은 iam-users에 있다 (같은 이름 `osi7-ecr-push`를 두 곳에서 만들면 apply가 실패한다).
- **iam**: 노드 역할(EKS worker + CNI + 프로젝트 ECR pull + AWS 관리형 `AmazonEC2ContainerRegistryPullOnly`)과 EKS 클러스터 역할을 만든다. Jenkins·ArgoCD 사용자는 iam-users에 있다.
- **eks**: app 서브넷에 클러스터를 만든다. Secrets는 KMS로 암호화하고, 컨트롤 플레인 로그는 모든 종류를 남기며, 인증 모드는 `API_AND_CONFIG_MAP`이다. 공개 엔드포인트는 `eks_public_access_cidrs`가 비어 있지 않을 때만 켜진다. 관리형 노드 그룹은 시작 템플릿으로 IMDSv2와 hop limit 1을 강제해 파드가 노드 권한을 쓰지 못하게 한다 (파드 권한은 Pod Identity/IRSA로 부여). EBS는 암호화된 gp3를 쓴다. 노드 그룹은 `desired_size` 변경을 무시하고, 애드온은 노드 그룹이 생긴 뒤에 설치한다. 팀원 kubectl 권한은 `access_entries`로 Access Entry와 액세스 정책을 붙인다 (namespaces가 비면 클러스터 전체). AWS Load Balancer Controller의 역할(`osi7-aws-load-balancer-controller`, 공식 정책 파일 `modules/eks/policies/`에 버전 고정)과 `kube-system/aws-load-balancer-controller` Pod Identity 연결도 만든다. 컨트롤러 설치(Helm)는 Terraform 밖이고, 설치 버전을 올리면 정책 파일도 같은 버전으로 바꾼다.

**DB는 온프레미스에서만 운영한다** (MySQL 8.4, GTID). AWS에는 RDS도, 클라우드 백업·복제도 두지 않는다. 그래서 EKS의 서비스는 온프레미스 연결을 통해 온프레미스 DB(3306)에 접속하며, 이 연결이 끊기면 AWS 쪽 앱도 DB를 쓸 수 없다. 노드 SG의 아웃바운드는 이미 전체 허용이라 SG 변경은 필요 없고, 경로만 추가하면 된다.

온프레미스 연결 방식(Site-to-Site VPN 또는 Tailscale 서브넷 라우터 등)은 아직 정해지지 않았다. 정해지면 그 모듈을 만들고, network의 `app_route_table_ids`에 온프레미스로 가는 경로를 넣는다. `onprem_cidr`는 그때까지 어디에도 쓰지 않는 임시값이다.

`docs/cli/`는 멘토 권장 순서(콘솔 → CLI → 정리 → Terraform)의 기록이다. network·security·ECR 1개·노드 IAM 역할을 Terraform과 같은 이름으로 CLI 스크립트(`01`~`04`, `99-cleanup.sh`)로 만들고 지운 뒤, `snapshot.sh`로 CLI 결과와 Terraform 결과를 ID 없이 비교한다 (QA A-IAC-01). CLI로 만든 것은 `ManagedBy=cli` 태그로 구분한다. CLI 리소스와 메인 Terraform을 동시에 올리면 같은 이름의 VPC가 두 개 생기므로, 반드시 정리한 뒤 apply한다. Terraform 모듈의 이름·규칙을 바꾸면 이 스크립트도 같이 맞춘다.

## 규칙

- 루트 변수는 `variables.tf`에 기본값과 함께 선언하고, 같은 값을 `terraform.tfvars`에도 적는다 (`terraform.tfvars`는 팀 엑셀 '변수' 시트와 대응). 값은 `terraform.tfvars`에서 수정하고, 변수를 추가할 때는 기본값도 함께 맞춘다. `onprem_cidr`, 노드 서비스 포트 범위, 노드 인스턴스 타입, k8s 버전 등은 팀원 확인을 기다리는 임시값이다.
- 비밀 값은 `secret.auto.tfvars`에 넣는다 (gitignore 대상).
- Checkov 예외는 `.checkov.yaml`이 아니라 해당 리소스 옆에 `#checkov:skip=CKV_...:<사유>` 주석으로 남기고, 사유를 꼭 적는다.
- 4주짜리 학습 프로젝트라서 비용을 아끼는 설정들은 의도한 것이며, 그 이유는 skip 주석에 적혀 있다. VPC Flow Logs 미사용, 로그 30일 보관, NAT 1개, 재구축 리허설용 `ecr_force_delete = true`가 해당한다.
