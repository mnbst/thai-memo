locals {
  enabled = var.ios_app_id != "" ? 1 : 0
}

# iOS は App Attest を使う（最低ターゲットが iOS 16 のため DeviceCheck は不要）
resource "google_firebase_app_check_app_attest_config" "ios" {
  count    = local.enabled
  provider = google-beta

  project   = var.project_id
  app_id    = var.ios_app_id
  token_ttl = "3600s"
}

# サービスごとの適用モード。ロールアウト初期は UNENFORCED にして
# Firebase コンソールの App Check メトリクスで「未証明リクエスト」が
# 十分減ったことを確認してから ENFORCED に上げる。
resource "google_firebase_app_check_service_config" "services" {
  for_each = local.enabled == 1 ? toset(var.enforced_services) : toset([])
  provider = google-beta

  project          = var.project_id
  service_id       = each.key
  enforcement_mode = var.enforcement_mode
}

# シミュレータ・CI 用デバッグトークン（実機の App Attest が使えない環境向け）
resource "google_firebase_app_check_debug_token" "simulator" {
  count    = local.enabled == 1 && var.debug_token != "" ? 1 : 0
  provider = google-beta

  project      = var.project_id
  app_id       = var.ios_app_id
  display_name = "Simulator / CI"
  token        = var.debug_token
}
