variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "ios_app_id" {
  description = "Firebase iOS アプリID (1:xxx:ios:xxx)。空の場合は App Check を構成しない。"
  type        = string
  default     = ""
}

variable "enforcement_mode" {
  description = <<-EOT
    App Check の適用モード。
    - OFF        : 完全無効
    - UNENFORCED : 検証はするが未証明リクエストも通す（メトリクス収集のみ。ロールアウト初期はこれ）
    - ENFORCED   : 未証明リクエストを拒否（旧バージョンのクライアントは弾かれる）
  EOT
  type        = string
  default     = "UNENFORCED"

  validation {
    condition     = contains(["OFF", "UNENFORCED", "ENFORCED"], var.enforcement_mode)
    error_message = "enforcement_mode は OFF / UNENFORCED / ENFORCED のいずれか。"
  }
}

variable "enforced_services" {
  description = "App Check を適用する Google サービス"
  type        = list(string)
  default = [
    "firestore.googleapis.com",
    "identitytoolkit.googleapis.com",
  ]
}

variable "debug_token" {
  description = "シミュレータ・CI 用のデバッグトークン（UUID）。空の場合は作成しない。dev/tester のみで使う。"
  type        = string
  default     = ""
  sensitive   = true
}
