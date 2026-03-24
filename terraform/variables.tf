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

# Subscription / IAP secrets
variable "play_service_account_key" {
  description = "Google Play Developer API サービスアカウントJSON"
  type        = string
  sensitive   = true
  default     = ""
}

variable "appstore_connect_key" {
  description = "App Store Connect API Key (p8)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "appstore_key_id" {
  description = "App Store Connect Key ID"
  type        = string
  default     = ""
}

variable "appstore_issuer_id" {
  description = "App Store Connect Issuer ID"
  type        = string
  default     = ""
}

# App Check
variable "ios_app_id" {
  description = "Firebase iOS App ID"
  type        = string
}

variable "android_app_id" {
  description = "Firebase Android App ID"
  type        = string
}

variable "app_check_ios_provider" {
  description = "iOSのApp Checkプロバイダー: attest または debug"
  type        = string
  default     = "debug"
}

variable "app_check_android_provider" {
  description = "AndroidのApp Checkプロバイダー: play_integrity または debug"
  type        = string
  default     = "debug"
}

variable "app_check_debug_token_ios" {
  description = "iOS用デバッグトークン（UUID形式）"
  type        = string
  sensitive   = true
  default     = ""
}

variable "app_check_debug_token_android" {
  description = "Android用デバッグトークン（UUID形式）"
  type        = string
  sensitive   = true
  default     = ""
}
