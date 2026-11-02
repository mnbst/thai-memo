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


variable "deploy_ci_secrets" {
  description = "Secret Manager に置く配信用 ci-* secret。null なら全部、[] なら作らない。"
  type        = list(string)
  default     = null
}
