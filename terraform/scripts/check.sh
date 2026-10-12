#!/usr/bin/env bash
# apply 전에 돌리는 점검 순서: fmt -> validate -> plan -> Checkov -> Infracost
#
# 사용법 (terraform 폴더에서):
#   ./scripts/check.sh           # AWS 자격 증명 없이 가능한 점검 (plan 제외)
#   ./scripts/check.sh --plan    # plan까지 실행하고, plan 파일 기준으로 Checkov/Infracost 실행
#
# 필요한 도구: terraform, checkov (pip install checkov), infracost (+ `infracost auth login`)
set -u
cd "$(dirname "$0")/.."

# 한국어 Windows에서 checkov가 한글 주석이 든 .checkov.yaml을 cp949로 읽다 실패하지 않게 한다
export PYTHONUTF8=1

WITH_PLAN=0
[ "${1:-}" = "--plan" ] && WITH_PLAN=1

FAILED=()
SKIPPED=()

run_step() {
  local name="$1" tool="$2"; shift 2
  echo
  echo "=== ${name} ==="
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "[건너뜀] ${tool} 이(가) 설치되어 있지 않습니다."
    SKIPPED+=("$name")
    return
  fi
  if "$@"; then
    echo "[통과] ${name}"
  else
    echo "[실패] ${name}"
    FAILED+=("$name")
  fi
}

run_step "terraform fmt" terraform terraform fmt -check -recursive
run_step "terraform init" terraform terraform init -backend=false -input=false
run_step "terraform validate" terraform terraform validate

PLAN_JSON=""
if [ "$WITH_PLAN" -eq 1 ]; then
  rm -f tfplan tfplan.json
  run_step "terraform plan" terraform terraform plan -input=false -out=tfplan
  # plan이 실패해도 terraform은 오류 표시가 된 tfplan을 남기므로, 성공했을 때만 plan 기준 점검을 한다
  if [[ ! " ${FAILED[*]-} " =~ " terraform plan " ]] && [ -f tfplan ]; then
    terraform show -json tfplan > tfplan.json && PLAN_JSON="tfplan.json"
  fi
fi

if [ -n "$PLAN_JSON" ]; then
  run_step "checkov (plan)" checkov checkov -f "$PLAN_JSON" --framework terraform_plan --compact --quiet --skip-download
  run_step "infracost (plan)" infracost infracost breakdown --path "$PLAN_JSON" --usage-file infracost-usage.yml
else
  run_step "checkov" checkov checkov --config-file .checkov.yaml
  run_step "infracost" infracost infracost breakdown --config-file infracost.yml
fi

echo
echo "=============== 요약 ==============="
[ ${#FAILED[@]} -gt 0 ]  && echo "실패: ${FAILED[*]}"
[ ${#SKIPPED[@]} -gt 0 ] && echo "건너뜀: ${SKIPPED[*]}"
if [ ${#FAILED[@]} -eq 0 ] && [ ${#SKIPPED[@]} -eq 0 ]; then
  echo "모든 점검 통과"
fi
[ ${#FAILED[@]} -eq 0 ]
