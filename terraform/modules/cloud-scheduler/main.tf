# Service account for Cloud Scheduler
resource "google_service_account" "scheduler" {
  account_id   = "cloud-scheduler"
  display_name = "Cloud Scheduler Service Account"
  description  = "Service account for Cloud Scheduler to invoke Cloud Functions"
  project      = var.project_id
}

# Grant Cloud Scheduler permission to invoke Cloud Functions
resource "google_project_iam_member" "scheduler_invoker" {
  project = var.project_id
  role    = "roles/cloudfunctions.invoker"
  member  = "serviceAccount:${google_service_account.scheduler.email}"
}

# Cloud Scheduler job for daily sentence generation
resource "google_cloud_scheduler_job" "daily_sentence_generation" {
  name        = "daily-sentence-generation"
  description = "Trigger daily Thai sentence generation at 10 AM JST"
  schedule    = "0 10 * * *"
  time_zone   = "Asia/Tokyo"
  region      = var.region
  project     = var.project_id

  http_target {
    http_method = "POST"
    uri         = "https://${var.region}-${var.project_id}.cloudfunctions.net/scheduledDailyGeneration"

    oidc_token {
      service_account_email = google_service_account.scheduler.email
    }
  }

  retry_config {
    retry_count = 3
  }

  depends_on = [google_project_iam_member.scheduler_invoker]
}
