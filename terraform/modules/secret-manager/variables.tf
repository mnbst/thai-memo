variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "project_number" {
  description = "GCP Project Number"
  type        = string
}

variable "gemini_api_key" {
  description = "Gemini API Key"
  type        = string
  sensitive   = true
}

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
