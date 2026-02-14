output "bigquery_dataset_id" {
  description = "BigQuery dataset ID for logs"
  value       = google_bigquery_dataset.logs_dataset.dataset_id
}

output "log_sink_name" {
  description = "Log sink name"
  value       = google_logging_project_sink.function_logs_to_bigquery.name
}
