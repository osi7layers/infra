#!/usr/bin/env bash
# QA 가중치 전환을 정해진 간격으로 자동 진행한다 (온프레미스:AWS = 80:20 -> 50:50 -> 20:80 -> 0:100).
# 단계마다 terraform/dns에서 weights/<단계>.tfvars로 apply(-auto-approve)하고, 적용 시각을 로그에 남긴 뒤 기다린다.
# 롤백(100:0)은 자동으로 하지 않는다. 멈추거나 되돌릴 때는 Ctrl+C로 중단하고 직접 apply한다:
#   cd terraform/dns && terraform apply -var-file=weights/100-0.tfvars
#
# 사용법 (terraform 폴더에서, Git Bash):
#   ./scripts/weight-rollout.sh               # 80-20부터 10분 간격
#   ./scripts/weight-rollout.sh 50-50         # 중간 단계부터 다시 시작 (중단 후 재개용)
#   INTERVAL_MIN=15 ./scripts/weight-rollout.sh
#
# 주의
#   - 가중치는 apply 후 DNS TTL(60초) 동안 이전 비율과 섞인다. 비율을 잴 때는 각 단계의 첫 1분을 빼고 본다.
#   - 문제가 있어도 다음 단계로 넘어간다. 대시보드를 보다가 롤백 기준에 걸리면 Ctrl+C 후 100-0을 apply한다.
#   - 전체 약 30분 + apply 시간. aws login 세션이 중간에 만료되지 않도록 시작 직전에 다시 로그인하고, PC가 잠자기에 들어가지 않게 한다.
set -euo pipefail
cd "$(dirname "$0")/../dns"

STEPS=(80-20 50-50 20-80 0-100)
INTERVAL_MIN="${INTERVAL_MIN:-10}"
START="${1:-80-20}"
LOG_DIR="logs"
mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/weight-rollout-$(date +%Y%m%d-%H%M%S).log"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG"; }

# 시작 단계 찾기
idx=-1
for i in "${!STEPS[@]}"; do [ "${STEPS[$i]}" = "$START" ] && idx=$i; done
[ "$idx" -ge 0 ] || { echo "단계는 ${STEPS[*]} 중 하나여야 합니다: $START"; exit 1; }

# 사전 확인: 자격 증명, AWS 쪽 레코드가 켜져 있는지
aws sts get-caller-identity --query Arn --output text >/dev/null || { echo "aws login --profile myungho 후 다시 실행하세요"; exit 1; }
grep -q '^aws_ingress_enabled *= *true' terraform.tfvars || { echo "terraform.tfvars의 aws_ingress_enabled가 true가 아닙니다 (ALB 레코드가 없으면 전환할 수 없음)"; exit 1; }

echo "진행할 단계: ${STEPS[*]:$idx} (간격 ${INTERVAL_MIN}분, 마지막 단계 후 종료. 롤백은 직접)"
echo "로그: terraform/dns/$LOG"
read -r -p "시작할까요? (yes 입력) " ans
[ "$ans" = "yes" ] || { echo "취소했습니다"; exit 1; }

log "시작: ${STEPS[*]:$idx}, 간격 ${INTERVAL_MIN}분"
trap 'log "중단됨 (마지막 적용 단계: ${current:-없음}). 롤백: terraform apply -var-file=weights/100-0.tfvars"' INT

for ((i = idx; i < ${#STEPS[@]}; i++)); do
  current="${STEPS[$i]}"
  log "적용 시작: 온프레미스:AWS = ${current/-/:}"
  if ! terraform apply -auto-approve -input=false -no-color -var-file="weights/$current.tfvars" >>"$LOG" 2>&1; then
    log "apply 실패: $current (자세한 내용은 로그). 여기서 멈춥니다"
    exit 1
  fi
  log "적용 완료: ${current/-/:} (DNS 반영까지 최대 1분)"

  if ((i < ${#STEPS[@]} - 1)); then
    next="${STEPS[$((i + 1))]}"
    log "${INTERVAL_MIN}분 대기 후 ${next/-/:}"
    sleep $((INTERVAL_MIN * 60))
  fi
done

log "마지막 단계(${current/-/:}) 적용 완료. 롤백은 직접: terraform apply -var-file=weights/100-0.tfvars"
