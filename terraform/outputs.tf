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

output "github_actions_play_upload_key" {
  description = "GitHub Actions Play アップロード用サービスアカウントキー (JSON) — GitHub Secret GOOGLE_PLAY_SERVICE_ACCOUNT_JSON にそのまま貼り付ける"
  value       = base64decode(google_service_account_key.github_actions_play_upload.private_key)
  sensitive   = true
}

output "wif_provider" {
  description = "GitHub Actions WIF プロバイダーリソース名 (ワークフローの workload_identity_provider に使用)"
  value       = var.github_repo != "" ? "projects/${data.google_project.project.number}/locations/global/workloadIdentityPools/github-actions-pool/providers/github-oidc-provider" : "WIF未設定 (github_repo変数を設定してください)"
}

output "ci_service_account" {
  description = "GitHub Actions が使用するサービスアカウント"
  value       = var.ci_service_account_email
}
