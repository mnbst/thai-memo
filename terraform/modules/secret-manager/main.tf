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

# --- Subscription / IAP secrets ---

# Google Play Developer API service account key
resource "google_secret_manager_secret" "play_service_account_key" {
  count     = var.play_service_account_key != "" ? 1 : 0
  secret_id = "play-service-account-key"
  project   = var.project_id

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "play_service_account_key_version" {
  count       = var.play_service_account_key != "" ? 1 : 0
  secret      = google_secret_manager_secret.play_service_account_key[0].id
  secret_data = var.play_service_account_key
}

resource "google_secret_manager_secret_iam_member" "play_service_account_key_accessor" {
  count     = var.play_service_account_key != "" ? 1 : 0
  secret_id = google_secret_manager_secret.play_service_account_key[0].id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${var.project_number}-compute@developer.gserviceaccount.com"
}

# App Store Connect API Key (p8)
resource "google_secret_manager_secret" "appstore_connect_key" {
  count     = var.appstore_connect_key != "" ? 1 : 0
  secret_id = "appstore-connect-key"
  project   = var.project_id

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "appstore_connect_key_version" {
  count       = var.appstore_connect_key != "" ? 1 : 0
  secret      = google_secret_manager_secret.appstore_connect_key[0].id
  secret_data = var.appstore_connect_key
}

resource "google_secret_manager_secret_iam_member" "appstore_connect_key_accessor" {
  count     = var.appstore_connect_key != "" ? 1 : 0
  secret_id = google_secret_manager_secret.appstore_connect_key[0].id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${var.project_number}-compute@developer.gserviceaccount.com"
}

# App Store Key ID
resource "google_secret_manager_secret" "appstore_key_id" {
  count     = var.appstore_key_id != "" ? 1 : 0
  secret_id = "appstore-key-id"
  project   = var.project_id

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "appstore_key_id_version" {
  count       = var.appstore_key_id != "" ? 1 : 0
  secret      = google_secret_manager_secret.appstore_key_id[0].id
  secret_data = var.appstore_key_id
}

resource "google_secret_manager_secret_iam_member" "appstore_key_id_accessor" {
  count     = var.appstore_key_id != "" ? 1 : 0
  secret_id = google_secret_manager_secret.appstore_key_id[0].id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${var.project_number}-compute@developer.gserviceaccount.com"
}

# App Store Issuer ID
resource "google_secret_manager_secret" "appstore_issuer_id" {
  count     = var.appstore_issuer_id != "" ? 1 : 0
  secret_id = "appstore-issuer-id"
  project   = var.project_id

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "appstore_issuer_id_version" {
  count       = var.appstore_issuer_id != "" ? 1 : 0
  secret      = google_secret_manager_secret.appstore_issuer_id[0].id
  secret_data = var.appstore_issuer_id
}

resource "google_secret_manager_secret_iam_member" "appstore_issuer_id_accessor" {
  count     = var.appstore_issuer_id != "" ? 1 : 0
  secret_id = google_secret_manager_secret.appstore_issuer_id[0].id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${var.project_number}-compute@developer.gserviceaccount.com"
}
