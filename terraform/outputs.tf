output "project_id" {
  description = "GCP Project ID"
  value       = var.project_id
}

output "region" {
  description = "GCP Region"
  value       = var.region
}

output "secret_name" {
  description = "Gemini API Key secret name"
  value       = module.secret_manager.secret_name
}

output "firebase_web_app_id" {
  description = "Firebase Web App ID"
  value       = module.firebase.web_app_id
}

output "firebase_config" {
  description = "Firebase configuration for Flutter app"
  value       = module.firebase.web_app_config
  sensitive   = true
}

output "bigquery_dataset_id" {
  description = "BigQuery dataset ID for logs analysis"
  value       = module.logging.bigquery_dataset_id
}

output "log_sink_name" {
  description = "Log sink name for Cloud Functions"
  value       = module.logging.log_sink_name
}
