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

# subscriptionStatus の定期実行（毎日 JST 0:00）
#
# 期限切れ premium を free に落とすフォールバック。Go 版は関数の形を環境で
# 分けない（常に HTTP トリガー）ので、定期実行の有無はこのジョブの有無で決まる。
# firebase-functions が作っていたジョブ（firebase-schedule-* ）と同じ形
# ―― OIDC トークン付きの HTTP POST ―― を Terraform 側で明示的に持つ。
resource "google_cloud_scheduler_job" "subscription_status" {
  count = var.enable_scheduled_jobs ? 1 : 0

  name        = "subscription-status-daily"
  project     = var.project_id
  region      = var.region
  description = "期限切れ premium ユーザーを free に戻す"

  schedule  = "0 0 * * *"
  time_zone = "Asia/Tokyo"

  # 関数側のタイムアウト(300s)より長く取る。
  attempt_deadline = "540s"

  http_target {
    http_method = "POST"
    uri         = "https://${var.region}-${var.project_id}.cloudfunctions.net/subscriptionStatus"

    # Cloud Run の invoker はこの SA に対して付ける必要がある。
    # 関数のランタイム SA と同じものを使う（既存ジョブと揃える）。
    oidc_token {
      service_account_email = "${data.google_project.project.number}-compute@developer.gserviceaccount.com"
      audience              = "https://${var.region}-${var.project_id}.cloudfunctions.net/subscriptionStatus"
    }
  }

  depends_on = [google_project_service.required_apis]
}

# dailyBatch — 毎日 JST 0:00 の深夜バッチ。
#
# クォータのリセット、UVM の P 減衰、匿名ユーザーと古い例文の掃除を行う。
# subscriptionStatus と同じく Go 版は常に HTTP トリガーなので、定期実行は
# このジョブが担う（dev では enable_scheduled_jobs = false で作らない）。
resource "google_cloud_scheduler_job" "daily_batch" {
  count = var.enable_scheduled_jobs ? 1 : 0

  name        = "daily-batch"
  project     = var.project_id
  region      = var.region
  description = "日次クォータのリセットと各種掃除"

  schedule  = "0 0 * * *"
  time_zone = "Asia/Tokyo"

  # 関数側のタイムアウト(1800s)に合わせる。全ユーザー走査があるため長い。
  attempt_deadline = "1800s"

  http_target {
    http_method = "POST"
    uri         = "https://${var.region}-${var.project_id}.cloudfunctions.net/dailyBatch"

    oidc_token {
      service_account_email = "${data.google_project.project.number}-compute@developer.gserviceaccount.com"
      audience              = "https://${var.region}-${var.project_id}.cloudfunctions.net/dailyBatch"
    }
  }

  depends_on = [google_project_service.required_apis]
}

# deliverDailySentence — 毎時起動の毎日例文配信。
#
# 現地の配信希望時刻に一致するユーザーへ例文を1件作って通知する。対象は
# notify_utc_hour で絞られるので、毎時走っても読み取りは 1日1回/ユーザー。
# Python 版は scheduler_fn.on_schedule でジョブごと自動生成していたが、
# Go 版は他のバッチと同じく HTTP トリガーなので定期実行はここが担う。
resource "google_cloud_scheduler_job" "deliver_daily_sentence" {
  count = var.enable_scheduled_jobs ? 1 : 0

  name        = "deliver-daily-sentence"
  project     = var.project_id
  region      = var.region
  description = "毎日例文の配信（毎時、現地時刻で判定）"

  schedule  = "0 * * * *"
  time_zone = "Etc/UTC"

  # 関数側のタイムアウト(540s)に合わせる。
  attempt_deadline = "540s"

  http_target {
    http_method = "POST"
    uri         = "https://${var.region}-${var.project_id}.cloudfunctions.net/deliverDailySentence"

    oidc_token {
      service_account_email = "${data.google_project.project.number}-compute@developer.gserviceaccount.com"
      audience              = "https://${var.region}-${var.project_id}.cloudfunctions.net/deliverDailySentence"
    }
  }

  depends_on = [google_project_service.required_apis]
}
