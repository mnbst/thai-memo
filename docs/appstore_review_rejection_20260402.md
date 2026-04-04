# App Store審査却下 対応リスト（2026-04-02）

審査ID: 5bcc575a-eb6c-45f8-993e-532fa5efbb63  
審査デバイス: iPad Air 11-inch (M3)  
対象バージョン: 1.0  
却下理由: ガイドライン 3.1.2（自動更新サブスクリプション）

---

## やること

### バイナリ（アプリ内）に追加

- [x] 利用規約（EULA）への機能するリンク → `paywall_screen.dart` に追加済み（2026-04-04）
- [x] プライバシーポリシーへの機能するリンク → `paywall_screen.dart` に追加済み（2026-04-04）
- [x] （確認）サブスクリプション名・期間・価格の表示が設定画面またはサブスク購入画面に存在するか → ペイウォール画面に月額価格・自動更新開示文あり、確認済み

### App Store Connect メタデータに追加

- [x] 利用規約（EULA）へのリンク
  - 標準Apple EULAを使う場合 → アプリ説明文にリンクを記載
  - カスタムEULAを使う場合 → App Store ConnectのカスタムEULA欄に追加
- [x] プライバシーポリシーへのリンク（App Store ConnectのURL欄に設定）

---

## 追加で対応が必要なこと（2026-04-04 審査前チェックで発見）

### バイナリ修正

~~- AdMob本番IDへの差し替え~~ → 現在広告非表示のためスルー

### 修正済み（コード）

- [x] `Info.plist` の未使用 `BGTaskSchedulerPermittedIdentifiers`（transistorsoft）を削除
- [x] `AppConfig.appVersion` を pubspec.yaml と一致する `1.2.0` に修正
- [x] `admob_service.dart` を `AppConfig.isProd` で環境分岐するよう整理

---

## 参考

- Apple Developer Program使用許諾契約 別紙2: https://developer.apple.com/support/downloads/terms/apple-developer-program/Apple-Developer-Program-License-Agreement-20240909.pdf
