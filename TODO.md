# TestFlight / Google Play 内部テスト 準備TODO

## Apple (TestFlight)

- [ ] Apple Developer Programに登録済みか確認
- [ ] App Store Connectでアプリを作成
- [ ] Bundle ID・署名証明書・Provisioning Profileを設定
- [ ] App Store Connectで課金商品 `premium_monthly`（月額自動更新サブスクリプション）を登録
- [ ] Sandboxテスターアカウントを作成（App Store Connect > ユーザとアクセス > Sandbox）
- [ ] StoreKit Configuration File (.storekit) を作成してローカルテスト環境を構築（任意）
- [ ] Xcodeでarchive → App Store Connectにアップロード
- [ ] TestFlightでテスターグループ作成・招待

## Google Play (内部テスト)

- [ ] Google Play Consoleに登録済みか確認
- [ ] Play Consoleでアプリを作成
- [ ] 署名鍵（upload key）を設定
- [ ] Play Consoleで課金商品 `premium_monthly`（月額サブスクリプション）を登録
- [ ] ライセンステスターのメールアドレスを設定（Play Console > 設定 > ライセンステスト）
- [ ] `flutter build appbundle` でAABをビルド
- [ ] 内部テストトラックにAABをアップロード（※課金商品登録にはAABが1回以上アップロード済みである必要あり）
- [ ] テスターのメールアドレスを追加・招待

## CI/CD シークレット設定

### GCP Secret Manager に登録が必要なもの（`thai-memo-67139` プロジェクト）

```
gcloud secrets versions add <name> --project=thai-memo-67139 --data-file=-
```

- [ ] `ci-app-specific-password` — Apple ID のアプリ用パスワード
- [ ] `ci-google-play-service-account` — Google Play サービスアカウント JSON（秘密鍵含む）
- [ ] `ci-keystore` — Android 署名鍵（.jks を base64 エンコード）
- [ ] `ci-key-password` — キーストアのキーパスワード
- [ ] `ci-store-password` — キーストアのストアパスワード
- [ ] `ci-p12-cert` — iOS 配布証明書（.p12 を base64 エンコード）
- [ ] `ci-p12-password` — .p12 証明書のパスワード
- [ ] `ci-provisioning-profile` — iOS プロビジョニングプロファイル（.mobileprovision を base64 エンコード）

### プロジェクト内管理に移行するもの（Secret Manager 不要）

- [ ] `ci-apple-id` → ワークフローの env にハードコード
- [ ] `ci-key-alias` → ワークフローの env にハードコード
- [ ] `ci-google-services-json` → `android/app/google-services.json` としてリポジトリにコミット
- [ ] `ci-google-service-info-plist` → `ios/Runner/GoogleService-Info.plist` としてリポジトリにコミット
- [ ] `ci-app-check-debug-token` → 使用しないため削除

## 将来対応

- [ ] ユーザーごとの推定語彙数（estimated_vocab）の日次推移を記録・可視化
  - `dailyBatch` で各ユーザーの `estimated_vocab` を `users/{uid}/vocab_history/{YYYY-MM-DD}` に書き込む
  - または BigQuery Export（Firestore → BigQuery）でまとめて集計
  - ユーザー数が増えてから対応

## 共通

- [ ] アプリのバージョン番号・ビルド番号を確認・設定
- [ ] Firebase等のバックエンド環境が正しく接続されているか確認
- [ ] verifySubscription Cloud Functionがデプロイ済みか確認
