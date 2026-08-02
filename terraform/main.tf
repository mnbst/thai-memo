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
    "artifactregistry.googleapis.com",
    "cloudbilling.googleapis.com",
    "pubsub.googleapis.com",
    "run.googleapis.com",
    "iamcredentials.googleapis.com",
    "iam.googleapis.com",
    "fcm.googleapis.com",
    "monitoring.googleapis.com",
    "billingbudgets.googleapis.com",
    "firebaseappcheck.googleapis.com",
  ])

  project = var.project_id
  service = each.key

  disable_on_destroy = false
}

# Cloud Functions ランタイムSA（デフォルトcompute SA）のIAM
# roles/editor には FCM 送信権限（cloudmessaging.messages.create）が含まれないため、
# deliverDailySentence の通知送信には sdkAdminServiceAgent が必要。
resource "google_project_iam_member" "functions_runtime_firebase_admin" {
  project = var.project_id
  role    = "roles/firebase.sdkAdminServiceAgent"
  member  = "serviceAccount:${data.google_project.project.number}-compute@developer.gserviceaccount.com"

  depends_on = [google_project_service.required_apis]
}

# Secret Manager module
module "secret_manager" {
  source = "./modules/secret-manager"

  project_id     = var.project_id
  project_number = data.google_project.project.number
  gemini_api_key = var.gemini_api_key
  openai_api_key = var.openai_api_key

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

  enable_firestore_protection = var.enable_firestore_protection

  depends_on = [google_project_service.required_apis]
}

# App Check module — iOS (App Attest)
module "app_check" {
  source = "./modules/app-check"

  project_id       = var.project_id
  ios_app_id       = var.ios_app_id
  enforcement_mode = var.app_check_enforcement_mode
  debug_token      = var.app_check_debug_token

  depends_on = [
    google_project_service.required_apis,
    module.firebase,
  ]
}

# Monitoring module — 予算アラート・監視アラート
module "monitoring" {
  source = "./modules/monitoring"

  project_id      = var.project_id
  alert_email     = var.alert_email
  billing_account = var.billing_account
  budget_amount   = var.budget_amount

  depends_on = [
    google_project_service.required_apis,
    module.logging,
  ]
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
    "roles/firebase.admin",
    "roles/secretmanager.secretAccessor",
  ] : []
}

resource "google_project_iam_member" "ci_service_account" {
  for_each = toset(local.ci_sa_roles)
  project  = var.project_id
  role     = each.value
  member   = "serviceAccount:${var.ci_service_account_email}"
}

# Workload Identity Federation for GitHub Actions
resource "google_iam_workload_identity_pool" "github_actions" {
  count                     = var.github_repo != "" ? 1 : 0
  project                   = var.project_id
  workload_identity_pool_id = "github-actions-pool"
  display_name              = "GitHub Actions Pool"

  depends_on = [google_project_service.required_apis]
}

resource "google_iam_workload_identity_pool_provider" "github" {
  count                              = var.github_repo != "" ? 1 : 0
  project                            = var.project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.github_actions[0].workload_identity_pool_id
  workload_identity_pool_provider_id = "github-oidc-provider"
  display_name                       = "GitHub OIDC Provider"

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }

  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.repository" = "assertion.repository"
    "attribute.ref"        = "assertion.ref"
  }

  # リポジトリに加えてブランチも固定する。
  # public 化するとフォークから任意のワークフローが読めるようになるため、
  # デプロイ用ブランチ（distribute-prod: main / distribute-test: test）以外からは
  # OIDC トークンを受け付けない。
  attribute_condition = "assertion.repository == '${var.github_repo}' && assertion.ref in ['refs/heads/main', 'refs/heads/test']"
}

resource "google_service_account_iam_member" "github_actions_wif" {
  count              = var.github_repo != "" && var.ci_service_account_email != "" ? 1 : 0
  service_account_id = "projects/${var.project_id}/serviceAccounts/${var.ci_service_account_email}"
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github_actions[0].name}/attribute.repository/${var.github_repo}"
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
    "handleappstorenotification",
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
