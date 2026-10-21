# ---------------------------------------------------------------- 비용 알림 (AWS Budgets)
# 2026-10-21 유료 플랜으로 바꿔서, 크레딧을 다 쓰면 카드로 청구된다 (Free plan처럼 계정이 닫히며 멈추지 않는다).
# 메인을 켜 둔 채 잊거나 destroy가 중간에 실패한 경우를 메일로 알린다. 메인 destroy와 상관없이 남도록 상시 루트인 여기에 둔다.
# 크레딧을 빼기 전 사용 금액으로 계산한다 (크레딧을 포함하면 크레딧이 남아 있는 동안 늘 $0이라 알림이 오지 않는다).
# 예산 2개까지 무료. 받는 주소는 secret.auto.tfvars의 budget_alert_emails (git 제외). 비어 있으면 만들지 않는다.
resource "aws_budgets_budget" "monthly" {
  count = length(var.budget_alert_emails) > 0 ? 1 : 0

  name         = "${var.project}-monthly-cost"
  budget_type  = "COST"
  limit_amount = tostring(var.budget_limit_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  cost_types {
    include_credit = false
    include_refund = false
  }

  # 실제 사용 금액이 단계별 금액을 넘으면
  dynamic "notification" {
    for_each = var.budget_actual_thresholds_usd

    content {
      comparison_operator        = "GREATER_THAN"
      threshold                  = notification.value
      threshold_type             = "ABSOLUTE_VALUE"
      notification_type          = "ACTUAL"
      subscriber_email_addresses = var.budget_alert_emails
    }
  }

  # 이번 달 예상 금액이 예산을 넘을 것 같으면
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = var.budget_alert_emails
  }
}
