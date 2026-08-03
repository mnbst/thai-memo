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

variable "openai_api_key" {
  description = "OpenAI API Key (sensitive)"
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

variable "alert_email" {
  description = "アラート通知先メールアドレス。空の場合は監視・予算アラートを作成しない。"
  type        = string
  default     = ""
}

variable "billing_account" {
  description = "請求先アカウントID。空の場合は予算アラートを作成しない。"
  type        = string
  default     = ""
}

variable "budget_amount" {
  description = "月次予算額（円）"
  type        = number
  default     = 5000
}

variable "enable_firestore_protection" {
  description = "Firestore の PITR・定期バックアップ・削除保護を有効化する（prod のみ想定）"
  type        = bool
  default     = false
}

variable "ios_app_id" {
  description = "Firebase iOS アプリID。App Check の構成に使用。空の場合は App Check 未構成。"
  type        = string
  default     = ""
}

variable "app_check_enforcement_mode" {
  description = "App Check の適用モード (OFF / UNENFORCED / ENFORCED)"
  type        = string
  default     = "UNENFORCED"
}

variable "app_check_debug_token" {
  description = "App Check デバッグトークン（dev/tester のシミュレータ用）。secrets/<env>.tfvars に置く。"
  type        = string
  default     = ""
  sensitive   = true
}
