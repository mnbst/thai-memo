variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "alert_email" {
  description = "アラート通知先メールアドレス。空の場合は通知チャネル・アラートポリシーを作成しない。"
  type        = string
  default     = ""
}

variable "billing_account" {
  description = "請求先アカウントID (0189A7-XXXXXX-XXXXXX 形式)。空の場合は予算アラートを作成しない。"
  type        = string
  default     = ""
}

variable "budget_amount" {
  description = "月次予算額（billing_currency 単位）"
  type        = number
  default     = 5000
}

variable "billing_currency" {
  description = "請求先アカウントの通貨コード。予算額の単位と一致させる必要がある。"
  type        = string
  default     = "JPY"
}

variable "error_rate_threshold" {
  description = "5分あたりの Cloud Run 5xx レスポンス数がこの値を超えたらアラート"
  type        = number
  default     = 10
}

variable "generation_spike_threshold" {
  description = "5分あたりの例文生成成功数がこの値を超えたらアラート（LLMコスト暴走検知）"
  type        = number
  default     = 100
}
