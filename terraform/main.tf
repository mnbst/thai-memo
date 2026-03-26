# Get project information
data "google_project" "project" {
  project_id = var.project_id
}

# Enable required APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "cloudfunctions.googleapis.com",
    "cloudbuild.googleapis.com",
    "secretmanager.googleapis.com",
    "firebase.googleapis.com",
    "identitytoolkit.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "logging.googleapis.com",
    "cloudscheduler.googleapis.com",
    "firestore.googleapis.com",
    "fcm.googleapis.com",
    "artifactregistry.googleapis.com",
    "cloudbilling.googleapis.com",
    "pubsub.googleapis.com",
    "run.googleapis.com",
  ])

  project = var.project_id
  service = each.key

  disable_on_destroy = false
}

# Secret Manager module
module "secret_manager" {
  source = "./modules/secret-manager"

  project_id     = var.project_id
  project_number = data.google_project.project.number
  gemini_api_key = var.gemini_api_key

  play_service_account_key = var.play_service_account_key
  appstore_connect_key     = var.appstore_connect_key
  appstore_key_id          = var.appstore_key_id
  appstore_issuer_id       = var.appstore_issuer_id

  depends_on = [google_project_service.required_apis]
}

# Firebase module
module "firebase" {
  source = "./modules/firebase"

  project_id   = var.project_id
  display_name = var.firebase_project_display_name
  region       = var.region

  google_client_id     = var.google_client_id
  google_client_secret = var.google_client_secret
  apple_client_id      = var.apple_client_id
  apple_team_id        = var.apple_team_id
  apple_key_id         = var.apple_key_id
  apple_private_key    = var.apple_private_key

  depends_on = [google_project_service.required_apis]
}

# Logging module for Cloud Functions logs and metrics
module "logging" {
  source = "./modules/logging"

  project_id = var.project_id
  region     = var.region

  depends_on = [google_project_service.required_apis]
}

# UVM data module — GCS bucket for vocabulary embeddings
module "uvm_data" {
  source = "./modules/uvm-data"

  project_id     = var.project_id
  project_number = data.google_project.project.number
  region         = var.region

  depends_on = [google_project_service.required_apis]
}

# Pub/Sub topic for Google Play Real-Time Developer Notifications
resource "google_pubsub_topic" "play_subscription_notifications" {
  name    = "play-subscription-notifications"
  project = var.project_id

  depends_on = [google_project_service.required_apis]
}

# Artifact Registry cleanup policy for Cloud Functions container images
resource "google_artifact_registry_repository" "gcf_artifacts" {
  project       = var.project_id
  location      = var.region
  repository_id = "gcf-artifacts"
  format        = "DOCKER"

  cleanup_policies {
    id     = "keep-latest"
    action = "KEEP"
    most_recent_versions {
      keep_count = 1
    }
  }

  cleanup_policies {
    id     = "delete-old"
    action = "DELETE"
    condition {
      older_than = "86400s"
    }
  }

  depends_on = [google_project_service.required_apis]
}

# CI/CD service account IAM bindings
locals {
  ci_sa_roles = var.ci_service_account_email != "" ? [
    "roles/iam.serviceAccountUser",
    "roles/serviceusage.serviceUsageConsumer",
    "roles/cloudscheduler.admin",
  ] : []
}

resource "google_project_iam_member" "ci_service_account" {
  for_each = toset(local.ci_sa_roles)
  project  = var.project_id
  role     = each.value
  member   = "serviceAccount:${var.ci_service_account_email}"
}

# Cloud Run IAM: callable な Cloud Functions (v2) に allUsers invoker を付与
# Firebase callable 関数は Cloud Run 上で動作するため、
# Cloud Run レベルで allUsers に invoker 権限がないとリクエストが到達できない。
# 関数内の req.auth チェックで Firebase Auth 認証は別途行われる。
locals {
  callable_functions = [
    # "generatebatchsentences",  # Cloud Run service が存在する場合のみ有効化
    "generatequiz",
    "generatethaisentence",
    "subscriptionstatus",
    "updateuvm",
    "verifysubscription",
  ]
}

resource "google_cloud_run_service_iam_member" "callable_invoker" {
  for_each = toset(local.callable_functions)

  project  = var.project_id
  location = var.region
  service  = each.key
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# GitHub Actions 用 Google Play アップロードサービスアカウント
resource "google_service_account" "github_actions_play_upload" {
  account_id   = "github-actions-play-upload"
  display_name = "GitHub Actions - Google Play Upload"
  project      = var.project_id
}

resource "google_service_account_key" "github_actions_play_upload" {
  service_account_id = google_service_account.github_actions_play_upload.name
}

# Cloud Functions module will be added after Functions code is ready
# module "cloud_functions" {
#   source = "./modules/cloud-functions"
#
#   project_id        = var.project_id
#   region            = var.region
#   secret_id         = module.secret_manager.secret_id
#
#   depends_on = [
#     google_project_service.required_apis,
#     module.secret_manager
#   ]
# }
