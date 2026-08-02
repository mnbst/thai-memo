# Thai Memo Infrastructure

Terraformを使用したGCPインフラ構築

## Prerequisites

- Terraform >= 1.0
- gcloud CLI
- GCPアカウントと請求先の設定

## Setup

### 1. GCPプロジェクトを作成

```bash
gcloud projects create thai-memo-backend --name="Thai Memo Backend"
gcloud config set project thai-memo-backend
```

### 2. 請求先を設定

```bash
# 請求アカウントIDを確認
gcloud beta billing accounts list

# プロジェクトに請求アカウントをリンク
gcloud beta billing projects link thai-memo-backend \
  --billing-account=YOUR_BILLING_ACCOUNT_ID
```

### 3. 認証情報を設定

```bash
gcloud auth application-default login
```

### 4. 変数ファイルを用意

環境ごとに 2 ファイルに分かれている（環境: `dev` / `tester` / `prod`）。

| ファイル | 内容 | git |
|---|---|---|
| `<env>.tfvars` | project_id, region, client_id など非機密設定 | 追跡する |
| `secrets/<env>.tfvars` | APIキー・client secret・Apple 秘密鍵 | **gitignore（絶対にコミットしない）** |

`secrets/<env>.tfvars` に定義する変数:

```hcl
gemini_api_key       = "..."
openai_api_key       = "..."
google_client_secret = "..."
apple_private_key    = "-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----"
```

各値の取得元とローテート手順は [`../docs/secret_rotation.md`](../docs/secret_rotation.md) を参照。

### 5. Terraformを初期化

```bash
terraform init -backend-config=backends/<env>.tfbackend -reconfigure
```

### 6. プランを確認 / 適用

**`-var-file` を 2 つ渡すこと。** 片方だけだと変数不足でエラーになる。

```bash
terraform plan  -var-file=<env>.tfvars -var-file=secrets/<env>.tfvars
terraform apply -var-file=<env>.tfvars -var-file=secrets/<env>.tfvars
```

## Firebase設定ファイルのダウンロード

Terraform適用後、Firebase設定ファイルをダウンロード：

### Firebase CLIを使用（推奨）

```bash
# Firebase CLIにログイン
firebase login

# プロジェクトを選択
firebase use thai-memo-backend

# Android用google-services.jsonをダウンロード
# （Firebase Consoleで Android アプリを追加した後）
firebase apps:sdkconfig android -o ../android/app/google-services.json

# iOS用GoogleService-Info.plistをダウンロード
# （Firebase Consoleで iOS アプリを追加した後）
firebase apps:sdkconfig ios -o ../ios/Runner/GoogleService-Info.plist
```

### Firebase Consoleから手動でダウンロード

1. [Firebase Console](https://console.firebase.google.com/)にアクセス
2. プロジェクト "Thai Memo Backend" を選択
3. プロジェクト設定 > 一般 > アプリ から設定ファイルをダウンロード

## 出力の確認

```bash
# Firebase設定を表示
terraform output -json firebase_config | jq

# シークレット名を表示
terraform output secret_name

# Web App IDを表示
terraform output firebase_web_app_id
```

## クリーンアップ

```bash
terraform destroy
```

## トラブルシューティング

### APIが有効化されていないエラー

```bash
# 手動でAPIを有効化
gcloud services enable cloudfunctions.googleapis.com
gcloud services enable cloudbuild.googleapis.com
gcloud services enable secretmanager.googleapis.com
gcloud services enable firebase.googleapis.com
gcloud services enable identitytoolkit.googleapis.com
```

### 権限エラー

```bash
# 現在のアカウントを確認
gcloud auth list

# プロジェクトのオーナー権限を確認
gcloud projects get-iam-policy thai-memo-backend
```

## 次のステップ

1. Firebase設定ファイルをダウンロード
2. Cloud Functionsを実装
3. Flutterアプリを更新
