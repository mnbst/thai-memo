project_id                    = "thai-memo-prod"
region                        = "asia-northeast1"
firebase_project_display_name = "Thai Memo Prod"
google_client_id              = "219961294368-6lf7vceshitof77mflvjm0jujcbok68j.apps.googleusercontent.com" # TODO: GCP Console > APIs & Services > Credentials から取得
apple_client_id               = "com.thaimemo.thaiMemo"
apple_team_id                 = "5KTT2C466P"
apple_key_id                  = "JGPGZZ5HRP"
ci_service_account_email      = "github-actions-deployer@thai-memo-prod.iam.gserviceaccount.com"
github_repo                   = "mnbst/thai-memo"
github_allowed_refs           = ["refs/heads/main"]
alert_email                   = "gcp.demo.776@gmail.com"
billing_account               = "0189A7-F96D31-DD85EC"
budget_amount                 = 10000
enable_firestore_protection   = true
ios_app_id                    = "1:219961294368:ios:88e70ed652a72f10b70645"

# X 投稿のテーマ。変えたら terraform apply するだけでよい（プッシュ不要）。
x_post_themes = "BLドラマ"

# 朝以外の X 投稿枠。Actions の実行に数分かかるので、投稿は指定時刻の数分後になる。
# 12:00 と 21:00 は例文ではなく Tips・ガイド（tools/x_post/study_posts.json）を出す。
x_post_extra_slots = {
  "1200" = { schedule = "0 12 * * *", kind = "tip" }
  "1700" = { schedule = "0 17 * * *", themes = "仕事" }
  "2100" = { schedule = "0 21 * * *", kind = "guide" }
}
