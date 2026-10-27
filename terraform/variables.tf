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

variable "github_allowed_refs" {
  description = "配信用 WIF が OIDC トークンを受け付けるブランチ。環境ごとに1本へ絞る。"
  type        = list(string)
  default     = ["refs/heads/main", "refs/heads/test"]
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

variable "enable_scheduled_jobs" {
  description = <<-EOT
    定期実行ジョブ（Cloud Scheduler）を作るか。

    dev では false にする。JS 版の isDevOnly() が dev だけスケジューラを外して
    いたのと同じ方針で、dev の関数は手で叩いたときだけ動く。
    Go 版の関数は環境によらず HTTP トリガーなので、定期実行の有無は
    このジョブの有無だけで決まる。
  EOT
  type        = bool
  default     = true
}

variable "github_dispatch_token" {
  description = <<-EOT
    X 投稿ワークフロー（post-daily-x.yml）を Cloud Scheduler から起動する
    GitHub の fine-grained PAT。対象リポジトリだけ・Actions: Read and write。
    secrets/prod.tfvars にだけ置く。空ならジョブを作らない。
  EOT
  type        = string
  default     = ""
  sensitive   = true
}

variable "x_post_themes" {
  description = "X 投稿で抽選するテーマ（カンマ区切り。タイ旅行,タイ生活,恋愛,BLドラマ,仕事）。空なら全部。"
  type        = string
  default     = ""
}

variable "x_post_extra_slots" {
  description = "朝の投稿に加える X 投稿の枠。キーはジョブ名の接尾辞、schedule は JST の cron、themes は x_post_themes と同じ書式、kind は sentence（例文）/ tip / guide。"
  type = map(object({
    schedule = string
    themes   = optional(string, "")
    kind     = optional(string, "sentence")
  }))
  default = {}
}
