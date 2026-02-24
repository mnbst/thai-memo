# まいにちタイ語

AIが毎日タイ語の例文を生成し、単語分解・発音・日本語訳付きで学習できるFlutterアプリです。

## 環境構成

`--dart-define=ENV=<環境名>` で切り替える3環境構成。

| 環境 | ENV値 | Firebaseプロジェクト | 用途 |
|------|--------|---------------------|------|
| dev | `dev`（デフォルト） | thai-memo-dev | 開発・デバッグ |
| tester | `tester` | thai-memo-67139 | テスター配布（App Distribution等） |
| prod | `prod` | thai-memo-prod | 本番リリース |

### 実行方法

```bash
# dev（デフォルト、ENV指定不要）
flutter run

# tester
flutter run --dart-define=ENV=tester

# prod
flutter run --dart-define=ENV=prod
```

### 仕組み

- `lib/core/config/app_config.dart` で `ENV` の値を判定
- `lib/main.dart` で環境に応じた `FirebaseOptions` を選択
  - dev → `DefaultFirebaseOptions`（`firebase_options_dev.dart`）
  - tester → `TesterFirebaseOptions`（`firebase_options_tester.dart`）
  - prod → `ProdFirebaseOptions`（`firebase_options_prod.dart`）

## Firebaseデータのライフサイクル

### Firestore コレクション

| パス | 内容 | 作成 | 削除 |
|------|------|------|------|
| `/users/{uid}` | FCMトークン・通知設定 | アプリ起動時（merge upsert） | なし（永続） |
| `/users/{uid}/sentences/{id}` | タイ語例文 | `generateThaiSentence` Cloud Function | **30日経過で自動削除**（`notificationBatch`が毎日0:00 JSTに実行） |
| `/users/{uid}/quiz_answers/{id}` | クイズ回答履歴 | クイズ回答時にアプリから書き込み | なし（永続蓄積） |
| `/users/{uid}/quiz_sessions/{id}` | クイズセッション結果 | クイズ完了時にアプリから書き込み | なし（永続蓄積） |
| `/quiz_queue/{id}` | 通知用クイズキュー | `notificationBatch`が毎日0:00 JSTに生成 | **毎日全削除して再生成**（実質TTL 24時間） |

### Firebase Auth

- **匿名認証**: アプリ初回起動時に自動作成。明示的な削除処理なし（Firebaseデフォルトの30日未使用で自動削除に依存）。

### FCM トークン

- `/users/{uid}.fcm_token` に保存。`onTokenRefresh`で自動更新。
- 送信エラー（`registration-token-not-registered`）発生時に`sendNotifications`がフィールドを削除。
