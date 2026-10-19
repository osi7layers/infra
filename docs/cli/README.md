# 콘솔 → CLI → 정리 → Terraform

멘토가 권장한 순서로 같은 인프라를 세 번 만들어 보고, 결과가 같은지 비교하는 기록이다. QA 테스트 A-IAC-01의 "단계별 구성 비교"가 이 기록을 쓴다. Terraform 코드는 이미 있으므로 앞의 세 단계를 채우고 비교 자료를 남긴다.

| 단계 | 하는 일 | 얻는 것 |
|---|---|---|
| 1. 콘솔 | 화면에서 직접 만들고 지운다 | 리소스와 옵션 이해 |
| 2. CLI | 이 폴더의 스크립트로 다시 만든다 | 재현 가능한 절차, 비교용 기록 (`snapshot-cli.txt`) |
| 3. 정리 | `99-cleanup.sh`로 전부 지운다 | 의존 순서 이해, 남는 리소스가 없는지 확인 |
| 4. Terraform | 메인 루트를 apply하고 CLI 결과와 비교한다 | plan No changes, 설정 차이 0 |

## 범위

네트워크(VPC, 서브넷 4개, IGW, NAT 1개, 라우트 테이블), SG 2개와 규칙, ECR 리포지토리 1개(`ecommerce/web`), IAM 노드 역할만 다룬다. EKS 클러스터와 노드 그룹은 만들고 지우는 데 각 15분 이상 걸리고 시간당 비용이 나가서 제외한다 (Terraform으로 생성·삭제를 이미 검증함).

## 주의

- **콘솔·CLI로 만든 것과 Terraform을 동시에 올리지 않는다.** 이름이 같은 VPC가 두 개 생기고 비교도 할 수 없다. 반드시 정리한 뒤 다음 단계로 간다.
- NAT 게이트웨이는 시간당 요금이 나간다(약 $0.06/시간 + EIP). 단계마다 확인이 끝나면 바로 지운다.
- 이름과 태그는 Terraform과 같게 맞춘다. CLI로 만든 것에는 `ManagedBy=cli`, Terraform은 `ManagedBy=terraform`이 붙어서 구분된다.
- 스크립트는 Git Bash에서 실행하고, `aws login --profile myungho`로 로그인되어 있어야 한다 (`AWS_PROFILE=terraform`).

## 1. 콘솔 단계 (체크리스트)

VPC 콘솔 → "VPC 등"의 마법사를 쓰지 말고 하나씩 만든다 (각 리소스의 관계를 보려고). 만드는 것마다 태그 `Project=osi7`, `ManagedBy=console`을 붙인다 (정리 후 남은 것을 태그로 찾으려고).

- [ ] VPC `osi7-vpc` 10.20.0.0/16, DNS 확인·DNS 호스트 이름 켜기
- [ ] 서브넷 `osi7-public-a` 10.20.0.0/24 (2a), `osi7-public-c` 10.20.1.0/24 (2c), `osi7-app-a` 10.20.10.0/24 (2a), `osi7-app-c` 10.20.11.0/24 (2c)
- [ ] 인터넷 게이트웨이 `osi7-igw` 만들고 VPC에 연결
- [ ] 탄력적 IP 할당 → NAT 게이트웨이 `osi7-nat-0` (public-a)
- [ ] 라우트 테이블 `osi7-rt-public`(0.0.0.0/0 → IGW, public 서브넷 2개 연결), `osi7-rt-app-a`·`osi7-rt-app-c`(0.0.0.0/0 → NAT, 각 app 서브넷 연결)
- [ ] SG `osi7-alb-sg`(인바운드 80/443 0.0.0.0/0), `osi7-node-sg`(ALB SG에서 APISIX 9080, 자기 자신 전체). ALB SG 아웃바운드는 노드 SG 9080만
- [ ] ECR `ecommerce/web` (태그 변경 불가, 푸시할 때 스캔)
- [ ] 화면 캡처를 남긴 뒤 **만든 반대 순서로 삭제** (ECR → SG 규칙 중 서로 참조하는 것 → SG → NAT 삭제(완료까지 대기) → EIP 해제 → 라우트 테이블 → 서브넷 → IGW 분리·삭제 → VPC)
- [ ] `aws resourcegroupstaggingapi get-resources --tag-filters Key=ManagedBy,Values=console`이 비어 있는지 확인 (삭제한 NAT는 한동안 남아 보이므로 NAT는 `describe-nat-gateways`의 상태가 `deleted`인지로 확인)

## 2~3. CLI 단계와 정리

```bash
cd docs/cli
./01-network.sh      # VPC, 서브넷, IGW, NAT (NAT 대기 1~3분)
./02-security.sh     # SG 2개와 규칙
./03-ecr.sh          # ECR 1개
./04-iam.sh          # 노드 역할과 정책
./snapshot.sh cli    # 결과를 snapshot-cli.txt에 기록
./99-cleanup.sh      # 반대 순서로 삭제, 마지막에 남은 리소스 확인
```

스크립트는 만든 ID를 `.state.env`(git 제외)에 적어 다음 스크립트와 정리 스크립트에 넘긴다. 중간에 실패해도 `99-cleanup.sh`는 만들어진 것까지만 지운다.

## 4. Terraform 단계와 비교

```bash
cd terraform && terraform apply          # 별도 터미널에서
terraform plan -detailed-exitcode; echo $?   # 0이면 No changes
cd ../docs/cli && ./snapshot.sh terraform
diff snapshot-cli.txt snapshot-terraform.txt
```

비교 결과는 `RECORD.md`에 적는다. 예상되는 차이는 아래뿐이다.

- ECR: Terraform은 리포지토리 5개, CLI는 1개 (`ecommerce/web`만 비교). 2026-10-14 콘솔·CLI 단계는 이름이 바뀌기 전이라 `osi-shop/frontend`로 했다. 그때 찍은 `snapshot-cli.txt`와 비교하면 ECR 이름도 다르게 나온다
- ECR 수명 주기 정책 설명 문구 (CLI는 Windows 한글 인코딩 문제로 영어). 보관 개수(10)는 같아야 한다
- IAM: 프로젝트 Pull 정책(`osi7-ecr-pull`)이 Terraform은 5개 리포지토리, CLI는 1개를 대상으로 한다. 연결된 정책 이름은 같아야 한다
- Terraform에는 EKS가 만든 클러스터 SG(`eks-cluster-sg-...`)가 추가로 있다
