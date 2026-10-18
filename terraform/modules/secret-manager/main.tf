resource "google_secret_manager_secret" "openai_api_key" {
  secret_id = "openai-api-key"
  project   = var.project_id

  replication {
    auto {}
  }
}

# 値は terraform 管理外（gcloud secrets versions add で手動設定）。
# secret_data を Terraform に渡すと tfstate に平文で残るため、管理から外した。
removed {
  from = google_secret_manager_secret_version.openai_api_key_version
  lifecycle {
    destroy = false
  }
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

# 値は terraform 管理外（openai と同じ理由）。
removed {
  from = google_secret_manager_secret_version.gemini_api_key_version
  lifecycle {
    destroy = false
  }
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

# TypeSafe Jev API key for the sentence quality judge (dailyBatch の品質監査)
# 値は terraform 管理外: gcloud secrets versions add typesafe-api-key --data-file=- で手動設定
resource "google_secret_manager_secret" "typesafe_api_key" {
  secret_id = "typesafe-api-key"
  project   = var.project_id

  replication {
    auto {}
  }

  lifecycle {
    ignore_changes = [labels]
  }
}

resource "google_secret_manager_secret_iam_member" "typesafe_api_key_accessor" {
  secret_id = google_secret_manager_secret.typesafe_api_key.id
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
    # X（Twitter）自動投稿の OAuth 1.0a 認証情報
    "x-api-key",
    "x-api-secret",
    "x-access-token",
    "x-access-token-secret",
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

# --- 専用 SA ごとのアクセス権 ---
# compute SA はプロジェクトの Editor を持つので、関数・CI は専用 SA で動かし、
# 読める secret をここで1本ずつ許可する。

locals {
  # Cloud Functions ランタイム SA（functions-runtime）が読む secret。
  runtime_secrets = [
    "openai-api-key",
    "gemini-api-key",
    "appstore-connect-key",
    "appstore-key-id",
    "appstore-issuer-id",
    "gmail-app-password",
    "typesafe-api-key",
  ]

  # 配信ワークフロー（distribute-*）が読む secret。X の鍵は渡さない。
  deploy_ci_secrets = [for s in local.ci_secrets : s if !startswith(s, "x-")]

  # X 投稿ワークフローが読む secret。
  x_post_secrets = concat([for s in local.ci_secrets : s if startswith(s, "x-")], ["gemini-api-key"])
}

resource "google_secret_manager_secret_iam_member" "runtime_accessor" {
  for_each  = var.runtime_service_account_email != "" ? toset(local.runtime_secrets) : toset([])
  project   = var.project_id
  secret_id = each.key
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${var.runtime_service_account_email}"

  depends_on = [
    google_secret_manager_secret.openai_api_key,
    google_secret_manager_secret.gemini_api_key,
    google_secret_manager_secret.appstore_secrets,
    google_secret_manager_secret.gmail_app_password,
    google_secret_manager_secret.typesafe_api_key,
  ]
}

resource "google_secret_manager_secret_iam_member" "deploy_ci_accessor" {
  for_each  = var.ci_service_account_email != "" ? toset(local.deploy_ci_secrets) : toset([])
  project   = var.project_id
  secret_id = google_secret_manager_secret.ci_secrets[each.key].secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${var.ci_service_account_email}"
}

resource "google_secret_manager_secret_iam_member" "x_post_accessor" {
  for_each  = var.x_post_service_account_email != "" ? toset(local.x_post_secrets) : toset([])
  project   = var.project_id
  secret_id = each.key
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${var.x_post_service_account_email}"

  depends_on = [
    google_secret_manager_secret.ci_secrets,
    google_secret_manager_secret.gemini_api_key,
  ]
}
