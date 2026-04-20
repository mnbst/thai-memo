resource "google_secret_manager_secret" "openai_api_key" {
  secret_id = "openai-api-key"
  project   = var.project_id

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "openai_api_key_version" {
  secret      = google_secret_manager_secret.openai_api_key.id
  secret_data = var.openai_api_key
}

resource "google_secret_manager_secret_iam_member" "openai_api_key_accessor" {
  secret_id = google_secret_manager_secret.openai_api_key.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${var.project_number}-compute@developer.gserviceaccount.com"
}

resource "google_secret_manager_secret" "gemini_api_key" {
  secret_id = "gemini-api-key"
  project   = var.project_id

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "gemini_api_key_version" {
  secret      = google_secret_manager_secret.gemini_api_key.id
  secret_data = var.gemini_api_key
}

# Grant Cloud Functions v2 (Compute Engine service account) access to the secret
resource "google_secret_manager_secret_iam_member" "function_secret_accessor" {
  secret_id = google_secret_manager_secret.gemini_api_key.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${var.project_number}-compute@developer.gserviceaccount.com"
}


# App Store Connect secrets (常に作成、値は手動で gcloud secrets versions add にて設定)
locals {
  appstore_secrets = [
    "appstore-connect-key",
    "appstore-key-id",
    "appstore-issuer-id",
  ]
}

resource "google_secret_manager_secret" "appstore_secrets" {
  for_each  = toset(local.appstore_secrets)
  secret_id = each.key
  project   = var.project_id

  replication {
    auto {}
  }

  lifecycle {
    ignore_changes = [labels]
  }
}

resource "google_secret_manager_secret_iam_member" "appstore_secrets_accessor" {
  for_each  = toset(local.appstore_secrets)
  secret_id = google_secret_manager_secret.appstore_secrets[each.key].id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${var.project_number}-compute@developer.gserviceaccount.com"
}

# Gmail App Password for sendContactEmail Cloud Function
resource "google_secret_manager_secret" "gmail_app_password" {
  secret_id = "gmail-app-password"
  project   = var.project_id

  replication {
    auto {}
  }

  lifecycle {
    ignore_changes = [labels]
  }
}

resource "google_secret_manager_secret_iam_member" "gmail_app_password_accessor" {
  secret_id = google_secret_manager_secret.gmail_app_password.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${var.project_number}-compute@developer.gserviceaccount.com"
}

# --- CI/CD secrets (GitHub Actions 用) ---
# 値は terraform 管理外: gcloud secrets versions add <name> --data-file=- で手動設定

locals {
  ci_secrets = [
    "ci-apple-id",
    "ci-app-specific-password",
    "ci-google-play-service-account",
    "ci-google-services-json",
    "ci-google-service-info-plist",
    "ci-keystore",
    "ci-key-alias",
    "ci-key-password",
    "ci-p12-cert",
    "ci-p12-password",
    "ci-provisioning-profile",
    "ci-store-password",
  ]
}

resource "google_secret_manager_secret" "ci_secrets" {
  for_each  = toset(local.ci_secrets)
  secret_id = each.key
  project   = var.project_id

  replication {
    auto {}
  }

  lifecycle {
    ignore_changes = [labels]
  }
}
