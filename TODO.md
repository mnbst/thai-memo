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

## 共通

- [ ] アプリのバージョン番号・ビルド番号を確認・設定
- [ ] Firebase等のバックエンド環境が正しく接続されているか確認
- [ ] verifySubscription Cloud Functionがデプロイ済みか確認
