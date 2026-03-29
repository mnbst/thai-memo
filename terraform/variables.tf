variable "project_id" {
  description = "GCP Project ID"
  type        = string
  default     = "thai-memo-67139"
}

variable "region" {
  description = "GCP region for resources"
  type        = string
  default     = "asia-northeast1"
}

variable "gemini_api_key" {
  description = "Gemini API Key (sensitive)"
  type        = string
  sensitive   = true
}

variable "firebase_project_display_name" {
  description = "Firebase project display name"
  type        = string
  default     = "Thai Memo (Tester)"
}

variable "ci_service_account_email" {
  description = "CI/CD用サービスアカウントのメールアドレス"
  type        = string
  default     = ""
}

variable "google_client_id" {
  description = "Google Sign-In OAuth client ID"
  type        = string
}

variable "google_client_secret" {
  description = "Google Sign-In OAuth client secret"
  type        = string
  sensitive   = true
}

variable "apple_client_id" {
  description = "Apple Sign-In Services ID"
  type        = string
}

variable "apple_team_id" {
  description = "Apple Developer Team ID"
  type        = string
}

variable "apple_key_id" {
  description = "Apple Sign-In Key ID"
  type        = string
}

variable "apple_private_key" {
  description = "Apple Sign-In private key (PEM format)"
  type        = string
  sensitive   = true
}


variable "github_repo" {
  description = "GitHub リポジトリ (owner/repo 形式)。WIF設定に使用。空の場合はWIF未設定。"
  type        = string
  default     = ""
}
