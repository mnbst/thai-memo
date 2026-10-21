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
    # Android の App Check（Play Integrity）。Play Console 側でもこのプロジェクトをリンクする
    "playintegrity.googleapis.com",
    # Google Play の購入検証（verifySubscription / handlePlayNotification）
    "androidpublisher.googleapis.com",
    # Play のクラッシュ率・ANR率（scripts/play_console.py vitals）
    "playdeveloperreporting.googleapis.com",
    # X 自動投稿の読み上げ音声（tools/x_post）
    "texttospeech.googleapis.com",
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

# Cloud Functions 専用ランタイム SA
#
# デフォルトの compute SA はプロジェクトの Editor を持ち、tfstate を含む全バケットや
# 全 secret に届く。公開関数1本の侵害が全体に波及しないよう、関数はこの SA で動かし、
# 必要な権限だけを付ける（secret は modules/secret-manager、バケットは下の uvm_data_*）。
#
# Google Play の購入検証（verifySubscription / handlePlayNotification）は ADC で
# Android Publisher API を呼ぶので、この SA を Play Console のユーザーに招待するまでは
# compute SA のまま動かす。
resource "google_service_account" "functions_runtime" {
  account_id   = "functions-runtime"
  display_name = "Cloud Functions runtime"
  project      = var.project_id
}

resource "google_project_iam_member" "functions_runtime" {
  for_each = toset([
    "roles/datastore.user",               # Firestore
    "roles/firebaseauth.admin",           # 匿名ユーザーの削除・ユーザー一覧（dailyBatch 等）
    "roles/firebasecloudmessaging.admin", # FCM 送信（cloudmessaging.messages.create）
    "roles/serviceusage.serviceUsageConsumer",
    "roles/logging.logWriter",
  ])
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.functions_runtime.email}"
}

resource "google_storage_bucket_iam_member" "uvm_data_runtime_reader" {
  bucket = module.uvm_data.bucket_name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.functions_runtime.email}"
}

# 例文プールだけ書き換えを許す（modules/uvm-data の cf_pool_writer と同じ条件）。
resource "google_storage_bucket_iam_member" "uvm_data_runtime_pool_writer" {
  bucket = module.uvm_data.bucket_name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.functions_runtime.email}"

  condition {
    title       = "corpus_pool_objects_only"
    description = "例文プールのオブジェクトだけ書き換えを許す"
    expression  = "resource.name.startsWith(\"projects/_/buckets/${module.uvm_data.bucket_name}/objects/corpus_pool_\")"
  }
}

# Secret Manager module
module "secret_manager" {
  source = "./modules/secret-manager"

  project_id     = var.project_id
  project_number = data.google_project.project.number

  # for_each の判定に使うので、apply 前に決まる形（SA の属性ではなく組み立てた文字列）で渡す。
  runtime_service_account_email = "functions-runtime@${var.project_id}.iam.gserviceaccount.com"
  ci_service_account_email      = var.ci_service_account_email
  x_post_service_account_email  = var.github_repo != "" && nonsensitive(var.github_dispatch_token != "") ? "github-actions-x-post@${var.project_id}.iam.gserviceaccount.com" : ""

  depends_on = [
    google_project_service.required_apis,
    google_service_account.functions_runtime,
    google_service_account.x_post,
  ]
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
  project_number  = data.google_project.project.number
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

# Google Play が RTDN をこのトピックへ発行するための権限。
# 無いと Play Console の「テスト通知を送信」も失敗し、更新・解約・返金が届かない。
resource "google_pubsub_topic_iam_member" "play_rtdn_publisher" {
  project = var.project_id
  topic   = google_pubsub_topic.play_subscription_notifications.name
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:google-play-developer-notifications@system.gserviceaccount.com"
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
  # 配信ワークフローは Secret Manager から署名鍵などを読むだけ。
  # secret は1本ずつ許可する（modules/secret-manager の deploy_ci_accessor）。
  ci_sa_roles = var.ci_service_account_email != "" ? [
    "roles/serviceusage.serviceUsageConsumer",
  ] : []

  # X 投稿ワークフロー。別の WIF プール・別の SA に分け、配信用の鍵に届かせない。
  x_post_workflow_ref_prefix = "${var.github_repo}/.github/workflows/post-daily-x.yml@"
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
  # 環境ごとのデプロイ用ブランチ（prod: main / tester: test）以外からは
  # OIDC トークンを受け付けない。X 投稿ワークフローは専用プールに分けたので弾く。
  attribute_condition = join(" && ", [
    "assertion.repository == '${var.github_repo}'",
    "assertion.ref in ${jsonencode(var.github_allowed_refs)}",
    "!assertion.workflow_ref.startsWith('${local.x_post_workflow_ref_prefix}')",
  ])
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
    "updateuvm",
    "verifysubscription",
  ]

  # Scheduler 以外から起動させない管理用 HTTP 関数。
  scheduled_functions = var.enable_scheduled_jobs ? toset([
    "subscriptionstatus",
    "dailybatch",
    "deliverdailysentence",
  ]) : toset([])
}

resource "google_cloud_run_service_iam_member" "callable_invoker" {
  for_each = toset(local.callable_functions)

  project  = var.project_id
  location = var.region
  service  = each.key
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# 関数側は呼び出し元を検証しないので、invoker は Scheduler の SA だけに限る。
# _member（追加型）だと --allow-unauthenticated で付いた allUsers が残るため
# （prod で dailybatch / deliverdailysentence が公開されていた）、_binding で上書きする。
# 旧 _member は消さずに管理から外す。destroy させると、同じメンバーを持つ
# _binding の作成と順序が前後したときに Scheduler の invoker が消える。
removed {
  from = google_cloud_run_service_iam_member.scheduled_invoker
  lifecycle {
    destroy = false
  }
}

resource "google_cloud_run_service_iam_binding" "scheduled_invoker" {
  for_each = local.scheduled_functions

  project  = var.project_id
  location = var.region
  service  = each.key
  role     = "roles/run.invoker"
  members  = ["serviceAccount:${data.google_project.project.number}-compute@developer.gserviceaccount.com"]
}

# GitHub Actions 用 Google Play アップロードサービスアカウント
resource "google_service_account" "github_actions_play_upload" {
  account_id   = "github-actions-play-upload"
  display_name = "GitHub Actions - Google Play Upload"
  project      = var.project_id
}

# 鍵は terraform 管理外（gcloud iam service-accounts keys create で作り、
# Secret Manager の ci-google-play-service-account に入れる）。
# Terraform で作ると秘密鍵が tfstate に残るため、管理から外した。
removed {
  from = google_service_account_key.github_actions_play_upload
  lifecycle {
    destroy = false
  }
}

# --- X 投稿ワークフロー（post-daily-x.yml）---
# 配信用と同じプールだと、X のジョブ（pip 依存やフォント取得を含む）から
# 署名鍵を読める SA に成り代われる。プールごと分け、このワークフローの
# main 実行だけを受け付ける。
resource "google_service_account" "x_post" {
  count        = var.github_repo != "" && var.github_dispatch_token != "" ? 1 : 0
  account_id   = "github-actions-x-post"
  display_name = "GitHub Actions - X post"
  project      = var.project_id
}

resource "google_project_iam_member" "x_post_usage" {
  count   = length(google_service_account.x_post)
  project = var.project_id
  role    = "roles/serviceusage.serviceUsageConsumer"
  member  = "serviceAccount:${google_service_account.x_post[0].email}"
}

# コーパスを読み、投稿済み記録（x_post/）だけ書く。
resource "google_storage_bucket_iam_member" "x_post_reader" {
  count  = length(google_service_account.x_post)
  bucket = module.uvm_data.bucket_name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.x_post[0].email}"
}

resource "google_storage_bucket_iam_member" "x_post_writer" {
  count  = length(google_service_account.x_post)
  bucket = module.uvm_data.bucket_name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.x_post[0].email}"

  condition {
    title       = "x_post_objects_only"
    description = "X 投稿の記録だけ書き換えを許す"
    expression  = "resource.name.startsWith(\"projects/_/buckets/${module.uvm_data.bucket_name}/objects/x_post/\")"
  }
}

resource "google_iam_workload_identity_pool" "github_x_post" {
  count                     = length(google_service_account.x_post)
  project                   = var.project_id
  workload_identity_pool_id = "github-x-post-pool"
  display_name              = "GitHub Actions X post"

  depends_on = [google_project_service.required_apis]
}

resource "google_iam_workload_identity_pool_provider" "github_x_post" {
  count                              = length(google_service_account.x_post)
  project                            = var.project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.github_x_post[0].workload_identity_pool_id
  workload_identity_pool_provider_id = "github-oidc-provider"
  display_name                       = "GitHub OIDC Provider"

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }

  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.repository" = "assertion.repository"
  }

  attribute_condition = join(" && ", [
    "assertion.repository == '${var.github_repo}'",
    "assertion.ref == 'refs/heads/main'",
    "assertion.workflow_ref.startsWith('${local.x_post_workflow_ref_prefix}')",
  ])
}

resource "google_service_account_iam_member" "x_post_wif" {
  count              = length(google_service_account.x_post)
  service_account_id = google_service_account.x_post[0].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github_x_post[0].name}/attribute.repository/${var.github_repo}"
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

# X への毎日投稿 — GitHub Actions の post-daily-x.yml を起動する。
#
# GitHub の schedule は数時間遅れたり飛んだりするので、時刻は Scheduler が
# 持ち、ワークフローは workflow_dispatch で起こす。本体は Flutter や ffmpeg が
# 要るので Actions 上のまま動かす。
resource "google_cloud_scheduler_job" "post_daily_x" {
  count = var.github_dispatch_token != "" ? 1 : 0

  name        = "post-daily-x"
  project     = var.project_id
  region      = var.region
  description = "X への毎日投稿ワークフローを起動する"

  # 07:00 JST。x_post_extra_slots と合わせて 5 時間おきに並べる。
  schedule  = "0 7 * * *"
  time_zone = "Asia/Tokyo"

  attempt_deadline = "30s"

  retry_config {
    retry_count = 3
  }

  http_target {
    http_method = "POST"
    uri         = "https://api.github.com/repos/${var.github_repo}/actions/workflows/post-daily-x.yml/dispatches"
    body = base64encode(jsonencode({
      ref    = "main"
      inputs = { themes = var.x_post_themes }
    }))

    headers = {
      "Authorization"        = "Bearer ${var.github_dispatch_token}"
      "Accept"               = "application/vnd.github+json"
      "Content-Type"         = "application/json"
      "X-GitHub-Api-Version" = "2022-11-28"
    }
  }

  depends_on = [google_project_service.required_apis]
}

# 朝以外の X 投稿枠（var.x_post_extra_slots）。中身は post_daily_x と同じ。
resource "google_cloud_scheduler_job" "post_daily_x_extra" {
  for_each = nonsensitive(var.github_dispatch_token != "") ? var.x_post_extra_slots : {}

  name        = "post-daily-x-${each.key}"
  project     = var.project_id
  region      = var.region
  description = "X への投稿ワークフローを起動する（${each.value.themes}）"

  schedule  = each.value.schedule
  time_zone = "Asia/Tokyo"

  attempt_deadline = "30s"

  retry_config {
    retry_count = 3
  }

  http_target {
    http_method = "POST"
    uri         = "https://api.github.com/repos/${var.github_repo}/actions/workflows/post-daily-x.yml/dispatches"
    body = base64encode(jsonencode({
      ref    = "main"
      inputs = { themes = each.value.themes }
    }))

    headers = {
      "Authorization"        = "Bearer ${var.github_dispatch_token}"
      "Accept"               = "application/vnd.github+json"
      "Content-Type"         = "application/json"
      "X-GitHub-Api-Version" = "2022-11-28"
    }
  }

  depends_on = [google_project_service.required_apis]
}
