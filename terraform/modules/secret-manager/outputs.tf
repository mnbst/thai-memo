output "secret_id" {
  description = "Secret Manager secret ID"
  value       = google_secret_manager_secret.gemini_api_key.secret_id
}

output "secret_name" {
  description = "Full secret name"
  value       = google_secret_manager_secret.gemini_api_key.name
}
