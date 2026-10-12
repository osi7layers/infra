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

버킷은 `terraform/bootstrap/`이 만든다. bootstrap은 별도의 Terraform 루트로, state를 로컬에 두고 계정마다 한 번만 apply한다. 버킷에는 `prevent_destroy`가 걸려 있다. 다른 계정으로 옮길 때는 그 계정에서 bootstrap을 apply한 뒤, 출력값 `state_bucket_name`으로 `backend.hcl`의 `bucket`을 바꾸고 `terraform init -backend-config=backend.hcl -reconfigure`를 한다 (기존 state를 옮길 거라면 `-migrate-state`).

## 구조

루트 `main.tf`가 `terraform/modules/` 아래 모듈 5개를 연결한다. 모듈 사이의 값은 모듈 출력으로만 주고받는다.

- **network**: VPC와 3계층 × AZ 2개 서브넷 (public / private app / private DB). public·app 서브넷에는 AWS Load Balancer Controller가 쓰는 `kubernetes.io/role/(internal-)elb` 태그가 붙어 있다. NAT 개수는 `nat_gateway_count`(1 또는 2)로 정한다. app 라우트 테이블은 `min(index, count-1)`로 NAT를 고르므로, NAT가 1개면 두 AZ가 같은 NAT를 쓴다. DB 서브넷에는 인터넷 경로가 없다.
- **security**: ALB / 노드 / DB 보안 그룹. ALB SG와 노드 SG가 서로를 참조하므로, 인라인 규칙 대신 `aws_vpc_security_group_*_rule` 리소스로 규칙을 따로 붙인다 (인라인으로 쓰면 순환 참조가 생긴다). 온프레미스 접근은 DB 포트와 복제용 egress만 `onprem_cidr`로 허용한다. 노드로 들어오는 온프레미스 규칙(SSH, 6443)은 일부러 두지 않았다. K8s API는 EKS 컨트롤 플레인에 있고, 노드 접속은 SSM으로 한다.
- **ecr**: `ecr_repositories`의 이름마다 `<ecr_namespace>/<이름>` 리포지토리를 만든다. namespace는 온프레미스 Harbor 프로젝트 이름과 같게 둔다. **iam** 모듈이 쓰는 pull/push IAM 정책도 이 모듈에서 만든다.
- **iam**: 노드 역할(EKS worker + CNI + osi-shop ECR pull + AWS 관리형 `AmazonEC2ContainerRegistryPullOnly`), EKS 클러스터 역할, 그리고 선택 사항인 Jenkins용 IAM 사용자를 만든다. Jenkins 사용자는 그룹을 통해 push 권한을 받는다. 액세스 키는 state에 비밀이 남지 않도록 Terraform이 아니라 콘솔에서 발급한다.
- **eks**: app 서브넷에 클러스터를 만든다. Secrets는 KMS로 암호화하고, 컨트롤 플레인 로그는 모든 종류를 남기며, 인증 모드는 `API_AND_CONFIG_MAP`이다. 공개 엔드포인트는 `eks_public_access_cidrs`가 비어 있지 않을 때만 켜진다. 관리형 노드 그룹은 시작 템플릿으로 IMDSv2와 hop limit 1을 강제해 파드가 노드 권한을 쓰지 못하게 한다 (파드 권한은 Pod Identity/IRSA로 부여). EBS는 암호화된 gp3를 쓴다. 노드 그룹은 `desired_size` 변경을 무시하고, 애드온은 노드 그룹이 생긴 뒤에 설치한다.

주석에 나오는 `vpn` 모듈은 아직 없다. 앞으로 만들 예정이며, `app_route_table_ids` / `db_route_table_id`에 VGW 경로 전파를 설정하는 역할이다.

## 규칙

- 루트 변수는 `variables.tf`에 기본값과 함께 선언하고, 같은 값을 `terraform.tfvars`에도 적는다 (`terraform.tfvars`는 팀 엑셀 '변수' 시트와 대응). 값은 `terraform.tfvars`에서 수정하고, 변수를 추가할 때는 기본값도 함께 맞춘다. `onprem_cidr`, 노드 서비스 포트 범위, 노드 인스턴스 타입, k8s 버전 등은 팀원 확인을 기다리는 임시값이다.
- 비밀 값은 `secret.auto.tfvars`에 넣는다 (gitignore 대상).
- Checkov 예외는 `.checkov.yaml`이 아니라 해당 리소스 옆에 `#checkov:skip=CKV_...:<사유>` 주석으로 남기고, 사유를 꼭 적는다.
- 4주짜리 학습 프로젝트라서 비용을 아끼는 설정들은 의도한 것이며, 그 이유는 skip 주석에 적혀 있다. VPC Flow Logs 미사용, 로그 30일 보관, NAT 1개, 재구축 리허설용 `ecr_force_delete = true`가 해당한다.
