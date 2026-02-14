variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "gemini_api_key" {
  description = "Gemini API Key"
  type        = string
  sensitive   = true
}
