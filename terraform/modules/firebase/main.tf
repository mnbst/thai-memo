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

# NOTE: Identity Platform Config disabled due to ADC auth issue
# Enable anonymous authentication manually in Firebase Console:
# https://console.firebase.google.com/project/thai-memo-67139/authentication/providers
# Or uncomment below and use service account credentials instead of ADC
#
# resource "google_identity_platform_config" "auth_config" {
#   provider = google-beta
#   project  = var.project_id

#   sign_in {
#     allow_duplicate_emails = false

#     anonymous {
#       enabled = true
#     }
#   }

#   depends_on = [google_firebase_project.default]
# }

# Get Firebase Web App config
data "google_firebase_web_app_config" "thai_memo_web_config" {
  provider   = google-beta
  project    = var.project_id
  web_app_id = google_firebase_web_app.thai_memo_web.app_id
}

# Firestore database
resource "google_firestore_database" "default" {
  project     = var.project_id
  name        = "(default)"
  location_id = var.region
  type        = "FIRESTORE_NATIVE"

  depends_on = [google_firebase_project.default]
}

# Firestore composite indexes
resource "google_firestore_index" "quiz_answers_is_correct_answered_at" {
  project    = var.project_id
  database   = "(default)"
  collection = "quiz_answers"

  fields {
    field_path = "is_correct"
    order      = "ASCENDING"
  }
  fields {
    field_path = "answered_at"
    order      = "DESCENDING"
  }

  depends_on = [google_firestore_database.default]
}
