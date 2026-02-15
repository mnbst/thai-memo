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
