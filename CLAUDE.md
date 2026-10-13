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

버킷은 `terraform/bootstrap/`이 만든다. bootstrap은 별도의 Terraform 루트로, state를 로컬에 두고 계정마다 한 번만 apply한다. 버킷에는 `prevent_destroy`가 걸려 있다. 버킷 이름은 `terraform/backend.hcl`과 `terraform/iam-users/backend.hcl` 두 곳에 있다. 다른 계정으로 옮길 때는 두 파일의 `bucket`을 bootstrap 출력값 `state_bucket_name`으로 바꾸고 `terraform init -backend-config=backend.hcl -reconfigure`를 한다 (기존 state를 옮길 거라면 `-migrate-state`).

지금 설정된 계정(`918633123181`, IAM 사용자 `sesac_cho`)은 테스트용이고, 실제 적용은 다른 계정에서 한다. 계정 ID는 코드에 적지 않고 `aws_caller_identity`로 읽으므로, 계정마다 바뀌는 곳은 위의 `backend.hcl` 두 개뿐이다.

### 새 계정에서 처음 적용하기

루트 계정은 처음 관리자 한 명을 만드는 데만 쓰고, 나머지는 모두 `myungho`로 한다.

1. 루트로 콘솔에 로그인해 루트 MFA를 켠다. 루트 액세스 키는 만들지 않는다.
2. 콘솔에서 IAM 사용자 `myungho`를 직접 만들고 `AdministratorAccess`를 임시로 붙인다. 이후 작업은 `aws login --profile myungho`로 로그인해서 한다.
3. `terraform/bootstrap`에서 `terraform init` → `terraform apply`로 state 버킷을 만든다.
4. `terraform/backend.hcl`, `terraform/iam-users/backend.hcl`의 `bucket`을 새 버킷 이름으로 바꾼다.
5. `terraform/iam-users`에서 `terraform init -backend-config=backend.hcl -reconfigure` 후, 콘솔에서 만든 사용자를 가져온다: `terraform import 'aws_iam_user.this["myungho"]' myungho`. 그다음 apply하면 그룹, 정책, 팀원이 만들어지고 `myungho`가 infra-admin 그룹에 들어간다.
6. 콘솔에서 `myungho`에 직접 붙였던 `AdministratorAccess`를 뗀다 (이제 그룹 권한을 받는다). 팀원 콘솔 비밀번호를 발급한다.
7. `terraform/`에서 `terraform init -backend-config=backend.hcl -reconfigure` 후 apply한다. 유료 플랜 계정이면 `eks_node_instance_types`를 실제 사양으로 바꾼다.

### 팀원 IAM (`terraform/iam-users/`)

팀원 IAM 사용자와 역할별 그룹(infra-admin, network, k8s-operator, cicd, observability, readonly, qa-k6)은 별도 루트 `terraform/iam-users/`가 만든다. 같은 버킷의 `iam-users/terraform.tfstate`를 써서, 메인을 destroy해도 팀원 계정은 남는다. 그 폴더에서 `terraform init -backend-config=backend.hcl` 후 apply하고, 팀원은 `users` 변수(사용자 이름 -> 그룹 목록)로 관리한다. 권한은 그룹에만 붙이고, 모든 그룹에 자기 자격 증명 관리 + 콘솔 MFA 강제 정책(`self-mfa`)이 붙는다. 이 정책은 `Bool` 조건이라 MFA 없는 콘솔만 막고 액세스 키(CLI)는 막지 않는다. 콘솔 비밀번호와 액세스 키는 콘솔에서 발급한다. 루트 계정은 프로젝트에 쓰지 않고, Terraform은 `myungho`(infra-admin)로 실행한다. `myungho`는 처음에 콘솔에서 만들어 import한다 (위 "새 계정에서 처음 적용하기").

kubectl 권한은 메인의 `eks_access_entries`(같은 사용자 이름 -> EKS 액세스 정책, 네임스페이스)가 eks 모듈의 Access Entry로 만든다. EKS는 없는 IAM 사용자로 Access Entry를 만들 수 없으므로 iam-users를 먼저 apply한다. 클러스터 생성자 자동 관리자(`bootstrap_cluster_creator_admin_permissions`)는 꺼 두었으므로 클러스터 관리자도 이 변수에 명시한다.

### 도메인 (`terraform/dns/`)

가비아에서 산 `osi7.shop` 전체를 Route 53에 위임한다. 별도 루트(`dns/terraform.tfstate`)로 둔 이유는 영역을 다시 만들면 네임서버 4개가 바뀌어 가비아 등록과 위임 대기를 다시 해야 하기 때문이며, 영역에는 `prevent_destroy`가 걸려 있다. 영역은 계정에 속하므로 실제 계정이 정해진 뒤 한 번만 만든다 (`dns/backend.hcl`의 `bucket`도 계정에 맞게 바꾼다).

1. `terraform/dns`에서 apply → 출력 `name_servers` 4개를 가비아 도메인 관리의 **네임서버 설정**에 입력 (NS 레코드 추가가 아님).
2. `nslookup -type=NS osi7.shop`에 awsdns 주소 4개가 나오면 위임 완료.
3. `harbor_ip`(harbor-01의 Tailscale IP)를 넣고 apply하면 `harbor.osi7.shop` A 레코드가 생긴다. Tailscale IP라 tailnet 안의 기기(Jenkins, 온프레미스 K8s 노드)에서만 접속된다.

Harbor 인증서(Let's Encrypt, DNS-01)는 첫 발급만 수동이다. 온프레미스 담당이 알려 주는 `_acme-challenge.harbor` TXT를 콘솔에서 넣고, 발급 후 지운다 (Terraform 코드에 없는 레코드라 apply가 건드리지 않는다). 그다음 `create_acme_user = true`로 apply해 자동 갱신용 사용자 `osi7-acme-harbor`를 만들고, 콘솔에서 액세스 키를 발급해 영역 ID(`zone_id` 출력)와 함께 전달한다. 이 사용자는 `acme_hosts`로 정한 `_acme-challenge.<호스트>.osi7.shop` TXT만 바꿀 수 있다. 인증서는 90일짜리이고 만료 30일 전에 갱신되므로, 첫 발급 후 60일 안에 자동화를 끝낸다.

## 구조

루트 `main.tf`가 `terraform/modules/` 아래 모듈 5개를 연결한다. 모듈 사이의 값은 모듈 출력으로만 주고받는다.

- **network**: VPC와 3계층 × AZ 2개 서브넷 (public / private app / private DB). public·app 서브넷에는 AWS Load Balancer Controller가 쓰는 `kubernetes.io/role/(internal-)elb` 태그가 붙어 있다. NAT 개수는 `nat_gateway_count`(1 또는 2)로 정한다. app 라우트 테이블은 `min(index, count-1)`로 NAT를 고르므로, NAT가 1개면 두 AZ가 같은 NAT를 쓴다. DB 서브넷에는 인터넷 경로가 없다.
- **security**: ALB / 노드 / DB 보안 그룹. ALB SG와 노드 SG가 서로를 참조하므로, 인라인 규칙 대신 `aws_vpc_security_group_*_rule` 리소스로 규칙을 따로 붙인다 (인라인으로 쓰면 순환 참조가 생긴다). 온프레미스 접근은 DB 포트와 복제용 egress만 `onprem_cidr`로 허용한다. 노드로 들어오는 온프레미스 규칙(SSH, 6443)은 일부러 두지 않았다. K8s API는 EKS 컨트롤 플레인에 있고, 노드 접속은 SSM으로 한다.
- **ecr**: `ecr_repositories`의 이름마다 `<ecr_namespace>/<이름>` 리포지토리를 만든다. namespace는 온프레미스 Harbor 프로젝트 이름과 같게 둔다. **iam** 모듈이 쓰는 pull/push IAM 정책도 이 모듈에서 만든다.
- **iam**: 노드 역할(EKS worker + CNI + osi-shop ECR pull + AWS 관리형 `AmazonEC2ContainerRegistryPullOnly`), EKS 클러스터 역할, 그리고 선택 사항인 Jenkins용 IAM 사용자를 만든다. Jenkins 사용자는 그룹을 통해 push 권한을 받는다. 액세스 키는 state에 비밀이 남지 않도록 Terraform이 아니라 콘솔에서 발급한다.
- **eks**: app 서브넷에 클러스터를 만든다. Secrets는 KMS로 암호화하고, 컨트롤 플레인 로그는 모든 종류를 남기며, 인증 모드는 `API_AND_CONFIG_MAP`이다. 공개 엔드포인트는 `eks_public_access_cidrs`가 비어 있지 않을 때만 켜진다. 관리형 노드 그룹은 시작 템플릿으로 IMDSv2와 hop limit 1을 강제해 파드가 노드 권한을 쓰지 못하게 한다 (파드 권한은 Pod Identity/IRSA로 부여). EBS는 암호화된 gp3를 쓴다. 노드 그룹은 `desired_size` 변경을 무시하고, 애드온은 노드 그룹이 생긴 뒤에 설치한다. 팀원 kubectl 권한은 `access_entries`로 Access Entry와 액세스 정책을 붙인다 (namespaces가 비면 클러스터 전체).

주석에 나오는 `vpn` 모듈은 아직 없다. 앞으로 만들 예정이며, `app_route_table_ids` / `db_route_table_id`에 VGW 경로 전파를 설정하는 역할이다.

## 규칙

- 루트 변수는 `variables.tf`에 기본값과 함께 선언하고, 같은 값을 `terraform.tfvars`에도 적는다 (`terraform.tfvars`는 팀 엑셀 '변수' 시트와 대응). 값은 `terraform.tfvars`에서 수정하고, 변수를 추가할 때는 기본값도 함께 맞춘다. `onprem_cidr`, 노드 서비스 포트 범위, 노드 인스턴스 타입, k8s 버전 등은 팀원 확인을 기다리는 임시값이다.
- 비밀 값은 `secret.auto.tfvars`에 넣는다 (gitignore 대상).
- Checkov 예외는 `.checkov.yaml`이 아니라 해당 리소스 옆에 `#checkov:skip=CKV_...:<사유>` 주석으로 남기고, 사유를 꼭 적는다.
- 4주짜리 학습 프로젝트라서 비용을 아끼는 설정들은 의도한 것이며, 그 이유는 skip 주석에 적혀 있다. VPC Flow Logs 미사용, 로그 30일 보관, NAT 1개, 재구축 리허설용 `ecr_force_delete = true`가 해당한다.
