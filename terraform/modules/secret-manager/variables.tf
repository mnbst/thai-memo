variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "project_number" {
  description = "GCP Project Number"
  type        = string
}

variable "runtime_service_account_email" {
  description = "Cloud Functions ランタイム SA。空なら secret を許可しない。"
  type        = string
  default     = ""
}

variable "ci_service_account_email" {
  description = "配信ワークフローの SA。空なら secret を許可しない。"
  type        = string
  default     = ""
}

variable "x_post_service_account_email" {
  description = "X 投稿ワークフローの SA。空なら secret を許可しない。"
  type        = string
  default     = ""
}

