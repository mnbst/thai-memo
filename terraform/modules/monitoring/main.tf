locals {
  alerts_enabled = var.alert_email != "" ? 1 : 0
  budget_enabled = var.alert_email != "" && var.billing_account != "" ? 1 : 0
}

# アラート通知先（メール）
resource "google_monitoring_notification_channel" "email" {
  count = local.alerts_enabled

  project      = var.project_id
  display_name = "Thai Memo Alerts (${var.project_id})"
  type         = "email"

  labels = {
    email_address = var.alert_email
  }
}

# 月次予算アラート。50/80/100% と、実績ベース120%で通知する。
resource "google_billing_budget" "monthly" {
  count = local.budget_enabled
  # billingbudgets API は quota project を要求する。google-beta 側に
  # user_project_override + billing_project が設定されているためこちらを使う。
  provider = google-beta

  billing_account = var.billing_account
  display_name    = "Thai Memo Monthly Budget (${var.project_id})"

  budget_filter {
    projects               = ["projects/${var.project_id}"]
    calendar_period        = "MONTH"
    credit_types_treatment = "INCLUDE_ALL_CREDITS"
  }

  amount {
    specified_amount {
      currency_code = var.billing_currency
      units         = tostring(var.budget_amount)
    }
  }

  dynamic "threshold_rules" {
    for_each = [0.5, 0.8, 1.0]
    content {
      threshold_percent = threshold_rules.value
      spend_basis       = "CURRENT_SPEND"
    }
  }

  threshold_rules {
    threshold_percent = 1.2
    spend_basis       = "FORECASTED_SPEND"
  }

  all_updates_rule {
    monitoring_notification_channels = [google_monitoring_notification_channel.email[0].id]
    # 請求先アカウントの管理者への既定通知は残す（disable_default_iam_recipients = false）
    disable_default_iam_recipients = false
  }
}

# Cloud Functions (Cloud Run) の 5xx 急増
resource "google_monitoring_alert_policy" "function_errors" {
  count = local.alerts_enabled

  project      = var.project_id
  display_name = "Cloud Functions 5xx エラー急増"
  combiner     = "OR"

  conditions {
    display_name = "5xx > ${var.error_rate_threshold} / 5min"

    condition_threshold {
      filter = join(" AND ", [
        "resource.type = \"cloud_run_revision\"",
        "metric.type = \"run.googleapis.com/request_count\"",
        "metric.labels.response_code_class = \"5xx\"",
      ])

      comparison      = "COMPARISON_GT"
      threshold_value = var.error_rate_threshold
      duration        = "0s"

      aggregations {
        alignment_period     = "300s"
        per_series_aligner   = "ALIGN_SUM"
        cross_series_reducer = "REDUCE_SUM"
        group_by_fields      = ["resource.labels.service_name"]
      }
    }
  }

  notification_channels = [google_monitoring_notification_channel.email[0].id]

  alert_strategy {
    auto_close = "3600s"
  }
}

# 例文生成の失敗急増（logging モジュールのログベース指標を使用）
resource "google_monitoring_alert_policy" "generation_failures" {
  count = local.alerts_enabled

  project      = var.project_id
  display_name = "例文生成の失敗急増"
  combiner     = "OR"

  conditions {
    display_name = "failed_sentence_generations > 5 / 5min"

    condition_threshold {
      filter = join(" AND ", [
        "resource.type = \"cloud_run_revision\"",
        "metric.type = \"logging.googleapis.com/user/failed_sentence_generations\"",
      ])

      comparison      = "COMPARISON_GT"
      threshold_value = 5
      duration        = "0s"

      aggregations {
        alignment_period     = "300s"
        per_series_aligner   = "ALIGN_SUM"
        cross_series_reducer = "REDUCE_SUM"
      }
    }
  }

  notification_channels = [google_monitoring_notification_channel.email[0].id]

  alert_strategy {
    auto_close = "3600s"
  }
}

# 例文生成の急増 = LLM コスト暴走の早期検知
resource "google_monitoring_alert_policy" "generation_spike" {
  count = local.alerts_enabled

  project      = var.project_id
  display_name = "例文生成の異常な急増（LLMコスト）"
  combiner     = "OR"

  conditions {
    display_name = "successful_sentence_generations > ${var.generation_spike_threshold} / 5min"

    condition_threshold {
      filter = join(" AND ", [
        "resource.type = \"cloud_run_revision\"",
        "metric.type = \"logging.googleapis.com/user/successful_sentence_generations\"",
      ])

      comparison      = "COMPARISON_GT"
      threshold_value = var.generation_spike_threshold
      duration        = "0s"

      aggregations {
        alignment_period     = "300s"
        per_series_aligner   = "ALIGN_SUM"
        cross_series_reducer = "REDUCE_SUM"
      }
    }
  }

  notification_channels = [google_monitoring_notification_channel.email[0].id]

  alert_strategy {
    auto_close = "3600s"
  }
}
