# Log metric for tracking successful generations
resource "google_logging_metric" "successful_generations" {
  name    = "successful_sentence_generations"
  project = var.project_id

  filter = <<-EOT
    resource.type="cloud_run_revision"
    resource.labels.service_name="generatethaisentence"
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
    resource.type="cloud_run_revision"
    resource.labels.service_name="generatethaisentence"
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
    resource.type="cloud_run_revision"
    resource.labels.service_name="generatethaisentence"
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

# App Check を通らない呼び出しが全体の日次上限に達した回数（functions/go/unverified_limit.go）。
# 達していればユーザー量産による LLM 課金の攻撃か、Play Integrity の大規模な不調。
resource "google_logging_metric" "appcheck_unverified_cap" {
  name    = "appcheck_unverified_cap"
  project = var.project_id

  filter = <<-EOT
    resource.type="cloud_run_revision"
    textPayload:"unverified limit reached reason=total"
  EOT

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    unit        = "1"
  }
}
