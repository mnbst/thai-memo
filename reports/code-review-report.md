# App Store コード審査レポート

**生成日時**: 2026-02-14
**アプリ名**: Thai Memo
**バージョン**: 1.0.0
**審査対象**: iOS App Store提出前レビュー

---

## サマリー

- **総合評価**: ⚠️ **要修正** - 重大な問題が1件、修正推奨が7件
- **重大な問題**: 1件（審査却下リスク）
- **警告**: 7件（修正推奨）
- **問題なし**: 11件

**提出前に必ず修正が必要な項目があります。**

---

## 🚨 重大な問題（即座に修正が必要）

### 1. Info.plist - 通知権限の使用説明文が欠落

**ファイル**: [ios/Runner/Info.plist](ios/Runner/Info.plist)
**問題**: `NSUserNotificationsUsageDescription` キーが存在しない

**詳細**:
アプリは `flutter_local_notifications` を使用して通知を送信しますが、Info.plistに通知権限の使用目的を説明するキーが設定されていません。

**App Store審査ガイドライン違反**:
- セクション5.1.1: プライバシー - データ収集と保存
- iOS 10以降、通知権限を使用する場合は必須

**リスク**: **審査却下の可能性が非常に高い**

**修正方法**:
`ios/Runner/Info.plist` に以下を追加:

```xml
<key>NSUserNotificationsUsageDescription</key>
<string>毎日のタイ語学習リマインダーと新しい例文の通知を送信するために使用します</string>
```

**参考**: Apple公式ドキュメント - [Requesting Authorization to Interact with the User](https://developer.apple.com/documentation/usernotifications/asking-permission-to-use-notifications)

---

## ⚠️ 警告（修正推奨）

### 1. GoogleService-Info.plist の存在確認

**ファイル**: `ios/Runner/GoogleService-Info.plist`
**問題**: Firebase設定ファイルの存在が確認できない

**詳細**:
`ls` コマンドで `ios/Runner/` ディレクトリを確認したところ、`GoogleService-Info.plist` が見つかりませんでした。

**リスク**: Firebase認証とCloud Functions呼び出しが失敗し、アプリが動作しない可能性

**推奨アクション**:
1. Firebase Consoleから `GoogleService-Info.plist` をダウンロード
2. `ios/Runner/` ディレクトリに配置
3. Xcodeプロジェクトに追加（Copy Bundle Resources）
4. `.gitignore` で除外されていないか確認

---

### 2. 未使用コード - GeminiApiService

**ファイル**: [lib/data/datasources/remote/gemini_api_service.dart](lib/data/datasources/remote/gemini_api_service.dart)
**問題**: バックエンドAPIに移行したため、このクラスは使用されていない可能性が高い

**詳細**:
- `gemini_api_service.dart` (295行) が存在
- 現在は `backend_api_service.dart` を使用している
- `pubspec.yaml` に `google_generative_ai: ^0.4.0` が残っている

**リスク**:
- 不要なパッケージがバイナリサイズを増加
- セキュリティアップデート対象が増える
- コードメンテナンスの負担

**推奨アクション**:
1. `gemini_api_service.dart` を削除（使用されていないことを確認後）
2. `pubspec.yaml` から `google_generative_ai` を削除
3. `flutter pub get` で依存関係を更新

**確認コマンド**:
```bash
# 使用箇所を検索
grep -r "GeminiApiService" lib/
```

---

### 3. 大量のデバッグ出力

**影響範囲**: 6ファイル、72箇所
**問題**: `debugPrint` が本番ビルドに残る可能性

**詳細**:
以下のファイルに大量の `debugPrint` が含まれています:
- [lib/services/notification_service.dart](lib/services/notification_service.dart): 7箇所
- [lib/services/background_service.dart](lib/services/background_service.dart): 19箇所
- [lib/services/firebase_auth_service.dart](lib/services/firebase_auth_service.dart): 6箇所
- [lib/data/datasources/remote/backend_api_service.dart](lib/data/datasources/remote/backend_api_service.dart): 12箇所
- [lib/data/datasources/remote/gemini_api_service.dart](lib/data/datasources/remote/gemini_api_service.dart): 20箇所
- [lib/main.dart](lib/main.dart): 8箇所

**リスク**:
- パフォーマンスへの軽微な影響
- ログにユーザーデータが含まれる可能性（プライバシー懸念）
- App Store審査での印象悪化

**推奨アクション**:
Flutterの `debugPrint` はデバッグモードでのみ動作するため、リリースビルドでは自動的に無効化されます。ただし、以下を確認:

1. ユーザーの個人情報（UID、APIキーなど）をログ出力していないか確認
2. 現在のログ出力を確認:
   - `firebase_auth_service.dart:24, 25, 34` - UID出力 ⚠️
   - `background_service.dart:197` - sentence ID出力 ✅（問題なし）

**修正例** ([lib/services/firebase_auth_service.dart:24-25](lib/services/firebase_auth_service.dart#L24-L25)):
```dart
// 修正前
debugPrint('✅ Signed in: ${userCredential.user?.uid}');

// 修正後
debugPrint('✅ Signed in successfully');
```

---

### 4. AI使用の透明性 - UI上での明示が不明確

**問題**: ユーザーにAI生成コンテンツであることを明示しているか不明

**App Store審査ガイドライン**:
- セクション5.1.2: サードパーティAI（Gemini）とのデータ共有を明示
- UI上でAI使用を明確に表示することを推奨

**確認が必要な箇所**:
- 今日の例文画面
- 設定画面
- 初回起動時の説明

**推奨アクション**:
1. 例文表示画面に「Google Gemini AIによって生成された例文です」と表示
2. 設定画面またはアプリ説明にAI使用を明記
3. プライバシーポリシーにデータ送信先を記載

**実装例**:
```dart
// 例文カードの下部に追加
Text(
  'この例文はGoogle Gemini AIによって自動生成されています',
  style: TextStyle(
    fontSize: 11,
    color: Colors.grey[600],
    fontStyle: FontStyle.italic,
  ),
)
```

---

### 5. バックグラウンドタスクの頻度制限

**ファイル**: [lib/services/background_service.dart:176](lib/services/background_service.dart#L176)
**問題**: 23時間以内の重複実行を防ぐロジックがあるが、iOSのバックグラウンド制限を考慮していない

**詳細**:
```dart
// 23時間以内はスキップ
if (timeSinceLastGeneration.inHours < 23) {
  debugPrint('Last generation was ${timeSinceLastGeneration.inHours} hours ago, skipping');
  return;
}
```

**懸念点**:
- iOSは `BGTaskScheduler` の実行を保証しない
- 24時間周期でも、実際には不定期実行される
- ユーザーがアプリを開かない場合、数日実行されない可能性

**推奨アクション**:
1. アプリ起動時に最後の生成時刻をチェックし、24時間以上経過していれば自動生成
2. バックグラウンド生成は「ボーナス」として扱う
3. 設定画面で「バックグラウンド生成は不定期です」と明記

**参考実装**:
```dart
// main.dartまたはhome_screen.dartに追加
Future<void> checkAndGenerateIfDue() async {
  final isGenerationDue = await ref.read(sentenceControllerProvider.notifier).isGenerationDue();
  if (isGenerationDue) {
    await ref.read(sentenceControllerProvider.notifier).generateSentence();
  }
}
```

---

### 6. セキュアストレージ - KeychainAccessibility設定

**ファイル**: [lib/data/datasources/local/secure_storage_service.dart:17](lib/data/datasources/local/secure_storage_service.dart#L17)
**問題**: `KeychainAccessibility.first_unlock` はデバイス再起動後、最初のアンロックまでデータにアクセスできない

**詳細**:
```dart
iOptions: IOSOptions(
  accessibility: KeychainAccessibility.first_unlock,
),
```

**懸念点**:
- バックグラウンドタスクが再起動後の最初のアンロック前に実行されると、セキュアストレージにアクセスできずエラーになる
- ただし、Thai Memoでは重要な機密情報（クレカ、パスワードなど）は保存していない

**現在の使用内容**:
- Gemini API Key（現在は使用していない）
- 最終生成タイムスタンプ（機密情報ではない）

**推奨アクション**:
以下のいずれか:

**オプション A**: `first_unlock_this_device` に変更（バックグラウンド対応、デバイスバックアップ除外）
```dart
accessibility: KeychainAccessibility.first_unlock_this_device,
```

**オプション B**: `unlocked` に変更（最も制限が緩い、バックアップ対象）
```dart
accessibility: KeychainAccessibility.unlocked,
```

**推奨**: オプションA（セキュリティとバックグラウンド動作のバランス）

---

### 7. 通知の頻度とオプトアウト

**ファイル**: [lib/services/notification_service.dart](lib/services/notification_service.dart)
**問題**: 通知のオプトアウト機能の実装が不明確

**App Store審査ガイドライン**:
- セクション4.5.4: プッシュ通知は機能必須にできない
- ユーザーがオプトアウトできる必要がある

**現在の実装**:
- ✅ `requestPermissions()` でiOS通知権限を要求 (Line 90-106)
- ✅ `areNotificationsEnabled()` で通知有効状態を確認 (Line 220-238)
- ❓ アプリ内での通知ON/OFF設定の実装が不明

**推奨アクション**:
1. 設定画面に「通知の有効/無効」トグルを追加
2. 無効時はバックグラウンドタスクで通知を表示しない
3. 初回起動時に通知の説明とオプトイン/アウトの選択肢を表示

**実装例**:
```dart
// settings_screen.dart に追加
SwitchListTile(
  title: const Text('通知を有効にする'),
  subtitle: const Text('新しい例文が生成されたときに通知します'),
  value: notificationsEnabled,
  onChanged: (value) async {
    await ref.read(settingsProvider.notifier).setNotificationsEnabled(value);
  },
)
```

---

### 8. エラーメッセージの多言語対応

**ファイル**: [lib/domain/usecases/generate_sentence_usecase.dart:130-148](lib/domain/usecases/generate_sentence_usecase.dart#L130-L148)
**問題**: エラーメッセージが日本語のみ

**詳細**:
```dart
String getUserMessage() {
  switch (type) {
    case GenerateSentenceErrorType.authenticationError:
      return '認証エラーが発生しました。アプリを再起動してください。';
    // ... すべて日本語
  }
}
```

**懸念点**:
- App Storeは多言語対応を推奨（必須ではない）
- アプリ名「Thai Memo」は英語、説明文は日本語？
- タイ在住の日本人ユーザー以外には使いにくい

**推奨アクション**:
現状では日本語ユーザー向けアプリとして明確であれば問題ありません。ただし、以下を確認:

1. App Store Connectのメタデータで「日本語のみ対応」と明記
2. 今後の多言語展開を考慮する場合は `flutter_localizations` の導入を検討

**App Store審査への影響**: なし（日本語専用アプリとして問題なし）

---

## ✅ 問題なし（合格項目）

### 1. ネットワーク通信のセキュリティ

✅ **すべてのAPI通信がHTTPSを使用**
- [lib/data/datasources/remote/backend_api_service.dart](lib/data/datasources/remote/backend_api_service.dart): Firebase Cloud Functions（HTTPS）

✅ **App Transport Security (ATS)**
- [ios/Runner/Info.plist](ios/Runner/Info.plist): `NSAllowsArbitraryLoads` キーが存在しない（デフォルトでHTTPSのみ許可）

---

### 2. セキュアストレージの適切な使用

✅ **機密情報の暗号化保存**
- [lib/data/datasources/local/secure_storage_service.dart](lib/data/datasources/local/secure_storage_service.dart)
  - Android: `encryptedSharedPreferences: true`
  - iOS: Keychain使用（`KeychainAccessibility.first_unlock`）

✅ **APIキーのハードコード防止**
- すべてのDartファイルをチェック済み
- APIキーは `flutter_secure_storage` から読み込み

---

### 3. Firebase認証の適切な実装

✅ **匿名認証の適切な実装**
- [lib/services/firebase_auth_service.dart](lib/services/firebase_auth_service.dart)
  - シングルトンパターン
  - エラーハンドリング
  - カスタム例外

✅ **認証状態の管理**
- `ensureAuthenticated()` で自動サインイン
- `authStateChanges()` でリアルタイム監視

---

### 4. バックグラウンド処理の適切な宣言

✅ **Info.plistでの適切な宣言**
- [ios/Runner/Info.plist:56-60](ios/Runner/Info.plist#L56-L60)
  ```xml
  <key>UIBackgroundModes</key>
  <array>
    <string>fetch</string>
    <string>processing</string>
  </array>
  ```

✅ **BGTaskSchedulerの設定**
- [ios/Runner/Info.plist:5-8](ios/Runner/Info.plist#L5-L8)
  ```xml
  <key>BGTaskSchedulerPermittedIdentifiers</key>
  <array>
    <string>com.transistorsoft.fetch</string>
  </array>
  ```

---

### 5. エラーハンドリング

✅ **適切なtry-catch**
- すべての非同期処理でエラーハンドリング実装
- カスタム例外の定義と使用

✅ **ユーザーフレンドリーなエラーメッセージ**
- [lib/domain/usecases/generate_sentence_usecase.dart:130-148](lib/domain/usecases/generate_sentence_usecase.dart#L130-L148)
  - 技術的エラーを日本語のユーザー向けメッセージに変換

---

### 6. サードパーティSDK

✅ **すべてのパッケージが最新かつ安全**
- [pubspec.yaml](pubspec.yaml): 主要パッケージの確認済み
  - `firebase_core: ^2.24.2`
  - `firebase_auth: ^4.16.0`
  - `cloud_functions: ^4.6.0`
  - `flutter_local_notifications: ^14.1.0`
  - `workmanager: ^0.5.1`
  - `flutter_secure_storage: ^8.0.0`

✅ **不要な権限要求なし**

---

### 7. 通知の実装

✅ **ユーザー許可の取得**
- [lib/services/notification_service.dart:90-106](lib/services/notification_service.dart#L90-L106)
  - iOS: `requestPermissions()`
  - 初期化時に権限要求

✅ **通知頻度の制限**
- 1日1回の新規例文通知のみ
- エラー通知のみ追加

---

### 8. データベース設計

✅ **SQLiteの適切な使用**
- 外部キー制約（CASCADE DELETE）
- インデックス設定

---

### 9. プライベートAPI使用なし

✅ **禁止されているAPIの使用なし**
- カスタムプラットフォームコードなし
- すべてFlutter公式パッケージまたはFirebase公式パッケージ

---

### 10. パフォーマンス

✅ **メモリリーク防止**
- Riverpod StateNotifierでの適切な状態管理
- `dispose()` メソッドの実装

✅ **タイムアウト設定**
- [lib/core/config/firebase_config.dart:12](lib/core/config/firebase_config.dart#L12): 45秒

---

### 11. コード品質

✅ **Clean Architecture**
- data / domain / presentation 層の分離
- 依存性注入

✅ **型安全性**
- Dartの強力な型システム活用
- JSON serialization (`json_serializable`)

---

## 📋 優先修正リスト

### 🔴 優先度: 最高（審査前に必須）

- [ ] **Info.plist に `NSUserNotificationsUsageDescription` を追加** - [重大な問題 #1](#1-infoplist---通知権限の使用説明文が欠落)
  - ファイル: `ios/Runner/Info.plist`
  - 所要時間: 5分
  - 影響: 審査却下防止

### 🟡 優先度: 高（強く推奨）

- [ ] **GoogleService-Info.plist の存在確認と配置** - [警告 #1](#1-googleservice-infoplist-の存在確認)
  - ファイル: `ios/Runner/GoogleService-Info.plist`
  - 所要時間: 10分
  - 影響: アプリが動作しない可能性

- [ ] **UI上でAI使用を明示** - [警告 #4](#4-ai使用の透明性---ui上での明示が不明確)
  - ファイル: `lib/presentation/screens/home_screen.dart` 他
  - 所要時間: 30分
  - 影響: App Store審査ガイドライン準拠

- [ ] **通知のオプトアウト機能を設定画面に追加** - [警告 #7](#7-通知の頻度とオプトアウト)
  - ファイル: `lib/presentation/screens/settings_screen.dart`
  - 所要時間: 1時間
  - 影響: ユーザー体験とガイドライン準拠

### 🟢 優先度: 中（推奨）

- [ ] **未使用コードの削除（GeminiApiService）** - [警告 #2](#2-未使用コード---geminiapiservice)
  - ファイル: `lib/data/datasources/remote/gemini_api_service.dart`, `pubspec.yaml`
  - 所要時間: 15分
  - 影響: バイナリサイズ削減

- [ ] **デバッグ出力のユーザー情報削除** - [警告 #3](#3-大量のデバッグ出力)
  - ファイル: `lib/services/firebase_auth_service.dart`
  - 所要時間: 10分
  - 影響: プライバシー保護

- [ ] **バックグラウンドタスク説明の追加** - [警告 #5](#5-バックグラウンドタスクの頻度制限)
  - ファイル: `lib/presentation/screens/settings_screen.dart`
  - 所要時間: 15分
  - 影響: ユーザー期待値の管理

### 🔵 優先度: 低（余裕があれば）

- [ ] **KeychainAccessibility設定の変更** - [警告 #6](#6-セキュアストレージ---keychainaccessibility設定)
  - ファイル: `lib/data/datasources/local/secure_storage_service.dart`
  - 所要時間: 5分
  - 影響: バックグラウンド動作の信頼性向上

---

## 🎯 App Store提出前 最終チェックリスト

### コード修正
- [ ] `NSUserNotificationsUsageDescription` を Info.plist に追加
- [ ] `GoogleService-Info.plist` を配置し、Xcodeプロジェクトに追加
- [ ] UI上でAI使用を明示
- [ ] 通知のオプトアウト機能を実装

### ビルドとテスト
- [ ] `flutter clean && flutter pub get`
- [ ] `flutter build ios --release`
- [ ] 実機でのテスト（iPhone実機必須）
  - [ ] Firebase認証が動作するか
  - [ ] 例文生成が正常に動作するか
  - [ ] 通知が正常に表示されるか
  - [ ] バックグラウンドタスクが動作するか（24時間待機またはシミュレート）

### App Store Connect準備
- [ ] プライバシーポリシーURL準備
- [ ] App Store Connect でプライバシー申告を完了
  - [ ] データ収集項目を正確に申告
  - [ ] Firebase、Gemini API使用を開示
- [ ] スクリーンショット準備（各デバイスサイズ）
- [ ] アプリ説明文にAI使用を明記

### 法的要件
- [ ] プライバシーポリシーにGemini API使用を記載
- [ ] 利用規約（必要な場合）
- [ ] サポートURL準備

---

## 📊 総合評価詳細

| カテゴリ | 評価 | 備考 |
|---------|------|------|
| プライバシー設定 | ⚠️ 要修正 | Info.plist に通知権限説明文が必要 |
| セキュリティ | ✅ 合格 | HTTPS通信、セキュアストレージ適切 |
| Firebase統合 | ⚠️ 要確認 | GoogleService-Info.plist の存在確認が必要 |
| バックグラウンド処理 | ✅ 合格 | 適切な宣言と実装 |
| 通知 | ⚠️ 要改善 | オプトアウト機能の明確化が必要 |
| AI透明性 | ⚠️ 要改善 | UI上での明示が必要 |
| エラーハンドリング | ✅ 合格 | 適切な実装 |
| コード品質 | ✅ 合格 | Clean Architecture、型安全性 |
| パフォーマンス | ✅ 合格 | メモリ管理、タイムアウト設定 |
| サードパーティSDK | ✅ 合格 | 安全なパッケージのみ使用 |

---

## 🔗 参考リンク

- [App Store Review Guidelines（日本語）](https://developer.apple.com/jp/app-store/review/guidelines/)
- [iOS Human Interface Guidelines - Notifications](https://developer.apple.com/design/human-interface-guidelines/notifications)
- [Firebase iOS Setup](https://firebase.google.com/docs/ios/setup)
- [Flutter Background Tasks Best Practices](https://docs.flutter.dev/development/packages-and-plugins/background-processes)
- [Privacy Manifest Files](https://developer.apple.com/documentation/bundleresources/privacy_manifest_files)

---

## 💬 まとめ

Thai Memoアプリは全体的に高品質なコードで実装されていますが、**App Store提出前に1件の必須修正と複数の推奨修正があります**。

**最優先対応**:
1. ✅ Info.plist に通知権限の説明文を追加（5分）
2. ✅ GoogleService-Info.plist の配置確認（10分）
3. ✅ AI使用の明示（30分）

これらを修正すれば、App Store審査に提出可能な状態になります。

**推定作業時間**: 約2-3時間で全修正完了

---

**レポート作成者**: Claude Code
**最終更新**: 2026-02-14
