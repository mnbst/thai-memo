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
