output "notification_channel_id" {
  description = "アラート通知チャネルのID（未作成の場合は空文字）"
  value       = var.alert_email != "" ? google_monitoring_notification_channel.email[0].id : ""
}
