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

# Identity Platform Config
resource "google_identity_platform_config" "auth_config" {
  provider = google-beta
  project  = var.project_id

  sign_in {
    allow_duplicate_emails = false

    anonymous {
      enabled = true
    }
  }

  depends_on = [google_firebase_project.default]
}

# Google Sign-In provider
resource "google_identity_platform_default_supported_idp_config" "google" {
  provider = google-beta
  project  = var.project_id
  idp_id   = "google.com"

  client_id     = var.google_client_id
  client_secret = var.google_client_secret

  enabled = true

  depends_on = [google_identity_platform_config.auth_config]
}

# Apple Sign-In provider (REST API経由 — Terraformリソースがteam_id/key_id/private_keyに未対応のため)
resource "null_resource" "apple_sign_in" {
  triggers = {
    apple_client_id = var.apple_client_id
    apple_team_id   = var.apple_team_id
    apple_key_id    = var.apple_key_id
  }

  provisioner "local-exec" {
    command = <<-EOT
      curl -s -X PATCH \
        -H "Authorization: Bearer $(gcloud auth print-access-token)" \
        -H "x-goog-user-project: ${var.project_id}" \
        -H "Content-Type: application/json" \
        -d '{
          "enabled": true,
          "clientId": "${var.apple_client_id}",
          "appleSignInConfig": {
            "codeFlowConfig": {
              "teamId": "${var.apple_team_id}",
              "keyId": "${var.apple_key_id}",
              "privateKey": ${jsonencode(var.apple_private_key)}
            }
          }
        }' \
        "https://identitytoolkit.googleapis.com/admin/v2/projects/${var.project_id}/defaultSupportedIdpConfigs/apple.com?updateMask=enabled,clientId,appleSignInConfig"
    EOT
  }

  depends_on = [google_identity_platform_config.auth_config]
}

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

resource "google_firestore_index" "quiz_queue_uid_sent_created_at" {
  project    = var.project_id
  database   = "(default)"
  collection = "quiz_queue"

  fields {
    field_path = "uid"
    order      = "ASCENDING"
  }
  fields {
    field_path = "sent"
    order      = "ASCENDING"
  }
  fields {
    field_path = "created_at"
    order      = "DESCENDING"
  }

  depends_on = [google_firestore_database.default]
}
