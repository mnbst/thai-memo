# App Store審査前 統合チェックレポート

生成日時: 2026-04-04  
アプリ名: まいにちタイ語  
バージョン: 1.2.0+0 (pubspec) / 1.0.0 (AppConfig)

---

## 総合評価

**現在の状態: 要修正**（提出前に3件の重大問題を解消すること）

### スコアカード

| チェック項目 | 状態 | 重大問題 | 警告 |
|------------|------|---------|------|
| コード品質 | 要修正 | 2件 | 2件 |
| プライバシー | 合格 | 0件 | 0件 |
| メタデータ | 警告あり | 0件 | 1件 |
| 総合審査 (3.1.2) | 要修正 | 1件 | 0件 |

---

## 重大な問題（即修正必須）

### 1. ペイウォール画面にEULA・プライバシーポリシーリンクなし【Guideline 3.1.2】

**前回却下理由と直結。**

`paywall_screen.dart` の購入セクション（`_buildPurchaseSection`）に、利用規約（EULA）とプライバシーポリシーへのリンクがない。  
自動更新の開示文はあるが、Appleはサブスクリプション購入UI内からEULA・プライバシーポリシーにアクセスできることを要求する。

**修正箇所**: `lib/presentation/screens/paywall_screen.dart`  
自動更新開示文の下（L221〜L235付近）に以下を追加:

```dart
// EULA・プライバシーポリシーリンク
Row(
  mainAxisAlignment: MainAxisAlignment.center,
  children: [
    TextButton(
      onPressed: () => launchUrl(Uri.parse(AppConfig.termsOfServiceUrl)),
      child: const Text('利用規約', style: TextStyle(fontSize: 12)),
    ),
    const Text('|'),
    TextButton(
      onPressed: () => launchUrl(Uri.parse(AppConfig.privacyPolicyUrl)),
      child: const Text('プライバシーポリシー', style: TextStyle(fontSize: 12)),
    ),
  ],
),
```

**App Store Connect側でも対応が必要:**
- App Store ConnectのアプリページにプライバシーポリシーURLを設定
- EULA欄に利用規約URLを設定（またはアプリ説明文に記載）

---

### 2. AdMob テスト用App IDが本番バイナリに混入【Guideline 2.3.1 / 4.3】

`Info.plist` L95:
```xml
<key>GADApplicationIdentifier</key>
<string>ca-app-pub-3940256099942544~1458002511</string>
```

`ca-app-pub-3940256099942544~1458002511` はGoogleが公開しているデモ用テストIDであり、本番アプリには使用不可。  
実際のAdMob App IDに差し替えが必要。

**修正**: Xcode Build Settings または `--dart-define` で環境別に差し替えるか、  
`ios/Runner/Info.plist` を本番AdMob App IDに更新する。

---

### 3. `com.transistorsoft.fetch` がpubspecに依存なし【Guideline 2.5.4】

`Info.plist` L6-8:
```xml
<key>BGTaskSchedulerPermittedIdentifiers</key>
<array>
    <string>com.transistorsoft.fetch</string>
</array>
```

`pubspec.yaml` に `background_fetch` や `flutter_background_fetch`（Transistor Software製）の依存が存在しない。  
このエントリが不要な場合、審査官から「未使用のバックグラウンド処理の宣言」として指摘される可能性がある。

**修正選択肢:**
- 不要なら `BGTaskSchedulerPermittedIdentifiers` エントリをInfo.plistから削除
- 必要なら適切なタスクIDに変更（例: `com.yourcompany.thai-memo.fetch`）

---

## 警告（修正推奨）

### W1. バージョン番号の不一致

- `pubspec.yaml`: `1.2.0+0`
- `lib/core/config/app_config.dart`: `1.0.0`（ハードコード）

Settings画面のバージョン表示が古い値になる。  
**修正**: `AppConfig.appVersion` を `pubspec.yaml` の値と同期、またはビルド時に動的取得する（`package_info_plus` パッケージを使用）。

### W2. プッシュ通知の権限フロー確認

`UIBackgroundModes` に `remote-notification` がある（デイリー通知機能のため）。  
アラート通知の権限リクエスト時にユーザーへの説明が適切に表示されるか、実機で確認すること。

---

## 合格項目

- プライバシーポリシー: 日英両言語、2026-04-04更新済み ✓
- 利用規約: 存在確認済み ✓
- Settings画面にプライバシーポリシー・利用規約リンクあり ✓
- ペイウォールに自動更新開示文あり（iOS限定、Guideline 3.1.2準拠） ✓
- APIキーのハードコードなし（環境変数・Secret Manager管理） ✓
- アカウント削除機能あり（Guideline 5.1.1準拠） ✓
- Google/Apple Sign-in実装 ✓
- HTTPS通信のみ（Cloud Functions経由） ✓
- Gemini AI使用のCloud Functions経由（クライアントにAPIキーなし） ✓

---

## 提出前アクションプラン

### 今すぐ対応（提出ブロッカー）

1. **paywall_screen.dart** にEULA・プライバシーポリシーリンクを追加
2. **Info.plist** の `GADApplicationIdentifier` を本番AdMob IDに変更
3. **Info.plist** の `BGTaskSchedulerPermittedIdentifiers` エントリを整理（不要なら削除）

### App Store Connect設定（提出前）

4. プライバシーポリシーURLを App Store Connect のアプリページに設定
5. EULA（利用規約）リンクをApp Store Connectに設定
6. サブスクリプション商品の価格・期間・説明が正確か確認

### 任意対応

7. `AppConfig.appVersion` を動的取得に変更
