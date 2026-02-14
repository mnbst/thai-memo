# Create Firebase project (links existing GCP project)
resource "google_firebase_project" "default" {
  provider = google-beta
  project  = var.project_id
}

# Create Firebase Web App
resource "google_firebase_web_app" "thai_memo_web" {
  provider     = google-beta
  project      = var.project_id
  display_name = "${var.display_name} Web"

  depends_on = [google_firebase_project.default]
}

# Enable Firebase Authentication
resource "google_identity_platform_config" "auth_config" {
  provider = google-beta
  project  = var.project_id

  # Enable anonymous authentication
  sign_in {
    allow_duplicate_emails = false

    anonymous {
      enabled = true
    }
  }

  depends_on = [google_firebase_project.default]
}

# Get Firebase Web App config
data "google_firebase_web_app_config" "thai_memo_web_config" {
  provider   = google-beta
  project    = var.project_id
  web_app_id = google_firebase_web_app.thai_memo_web.app_id
}
