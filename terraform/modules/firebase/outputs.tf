output "web_app_id" {
  description = "Firebase Web App ID"
  value       = google_firebase_web_app.thai_memo_web.app_id
}

output "web_app_config" {
  description = "Firebase Web App configuration"
  value       = data.google_firebase_web_app_config.thai_memo_web_config
  sensitive   = true
}
