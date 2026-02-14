# Log sink for exporting to BigQuery (optional - for long-term analysis)
resource "google_logging_project_sink" "function_logs_to_bigquery" {
  name        = "function-logs-to-bigquery"
  project     = var.project_id
  destination = "bigquery.googleapis.com/projects/${var.project_id}/datasets/${google_bigquery_dataset.logs_dataset.dataset_id}"

  # Filter for Cloud Functions logs
  filter = <<-EOT
    resource.type="cloud_function"
    resource.labels.function_name="generateThaiSentence"
    jsonPayload.userId!=""
  EOT

  # Use partitioned tables for better performance
  bigquery_options {
    use_partitioned_tables = true
  }

  # Grant BigQuery Data Editor role to the sink's service account
  unique_writer_identity = true
}

# BigQuery dataset for storing logs
resource "google_bigquery_dataset" "logs_dataset" {
  dataset_id  = "thai_memo_logs"
  project     = var.project_id
  location    = var.region
  description = "Logs from Thai Memo Cloud Functions"

  # Keep logs for 90 days
  default_table_expiration_ms = 7776000000 # 90 days in milliseconds

  labels = {
    environment = "production"
    application = "thai-memo"
  }
}

# Grant the sink's service account permission to write to BigQuery
resource "google_bigquery_dataset_iam_member" "sink_writer" {
  dataset_id = google_bigquery_dataset.logs_dataset.dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = google_logging_project_sink.function_logs_to_bigquery.writer_identity
}

# Log metric for tracking successful generations
resource "google_logging_metric" "successful_generations" {
  name    = "successful_sentence_generations"
  project = var.project_id

  filter = <<-EOT
    resource.type="cloud_function"
    resource.labels.function_name="generateThaiSentence"
    jsonPayload.success=true
  EOT

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    unit        = "1"

    labels {
      key         = "user_id"
      value_type  = "STRING"
      description = "User ID who generated the sentence"
    }
  }

  label_extractors = {
    "user_id" = "EXTRACT(jsonPayload.userId)"
  }
}

# Log metric for tracking failed generations
resource "google_logging_metric" "failed_generations" {
  name    = "failed_sentence_generations"
  project = var.project_id

  filter = <<-EOT
    resource.type="cloud_function"
    resource.labels.function_name="generateThaiSentence"
    jsonPayload.success=false
  EOT

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    unit        = "1"

    labels {
      key         = "error_code"
      value_type  = "STRING"
      description = "Error code"
    }
  }

  label_extractors = {
    "error_code" = "EXTRACT(jsonPayload.errorCode)"
  }
}

# Log metric for tracking processing time
resource "google_logging_metric" "processing_time" {
  name    = "sentence_generation_processing_time"
  project = var.project_id

  filter = <<-EOT
    resource.type="cloud_function"
    resource.labels.function_name="generateThaiSentence"
    jsonPayload.processingTimeMs!=""
  EOT

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "DISTRIBUTION"
    unit        = "ms"
  }

  value_extractor = "EXTRACT(jsonPayload.processingTimeMs)"

  bucket_options {
    exponential_buckets {
      num_finite_buckets = 64
      growth_factor      = 2
      scale              = 0.01
    }
  }
}
