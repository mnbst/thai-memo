# Android公開情報チェックリスト

最終更新: 2026-10-11

本番アプリ: `com.thaimemo.thai_memo`（Play Console「まいにちタイ語 - 毎日の例文で単語が増える」）。
tester 版は別アプリ `com.thaimemo.thai_memo.test`。

## 状況

- [x] アプリのコンテンツ（下記）をすべて申告
- [x] ストア掲載情報（ja-JP）を登録
- [x] クローズドテスト（Alpha）1.4.18 を審査に送信（2026-10-11）
- [ ] クローズドテストを 12 人以上 × 14 日間実施
- [ ] 製品版へのアクセスを申請
- [x] ストア掲載情報の英語（en-US / en-GB）を審査に送信（2026-10-13）

## 配信

- ワークフロー: `.github/workflows/distribute-prod-android.yml`（main から手動起動）
  - `gh workflow run distribute-prod-android.yml --ref main -f track=alpha`
  - versionCode は実行番号 + 300（Play に手で上げた 201 / 203 より大きくするため）
  - Play へは下書きで上がる。公開は Play Console で行う
- シークレット: prod の Secret Manager（`ci-keystore` ほか。アップロード鍵は tester と共通）
- アップロード用サービスアカウント: `github-actions-play-upload@thai-memo-prod.iam.gserviceaccount.com`
- 「管理対象の公開」はオフ。どこかで「保存して公開」を押すと、保留中の変更もまとめて審査に送られる

## 署名

| 鍵 | SHA-1 | prod Firebase |
|---|---|---|
| アプリ署名鍵（Play） | `7E:25:49:C6…9F:47` | 登録済み |
| アップロード鍵 | `32:13:47:FB…61:6A` | 登録済み |

## クローズドテスト

- テスター: Google グループ `thai-memo-testers@googlegroups.com`（誰でも参加可、メンバー一覧は管理者のみ）
- 参加ページ: https://groups.google.com/g/thai-memo-testers
- フィードバック: gcp.demo.776@gmail.com
- 特典（14日プレミアム）: Android アプリが `claimClosedTesterTrial` を呼んだとき（初回起動のペイウォール直前・以後の起動時）に一度だけ付く（`functions/go/closed_tester.go`）。1.4.19 以降のアプリが必要
  - 自動: `CLOSED_TEST_AUTO_GRANT_UNTIL`（RFC3339）までの間、App Check で Android アプリと確かめられた人。**製品版を公開したら外す**
    - 現在の値（暫定）: `2026-11-30T23:59:59+09:00`（prod の generateThaiSentence / startVocabTest）。延長・終了は `--update-env-vars` / `--remove-env-vars` で再デプロイ
  - 手動: prod Firestore の `closed_testers/{メール小文字}` に登録した人

## アプリのコンテンツ（申告内容）

| 項目 | 回答 |
|------|------|
| プライバシーポリシー | https://thai-memo-prod.web.app/privacy-policy.html |
| ログインの詳細 | 審査用のメール+パスワードアカウント（Firebase Auth）。手順: 設定 → サインイン → シートのタイトルを長押し → 入力。Google アカウントは本人確認で弾かれるため使わない |
| 広告 | なし |
| 広告 ID | 使用しない（AD_ID 系の権限はマニフェストで外している） |
| ターゲットユーザー | 13〜15歳 / 16〜17歳 / 18歳以上 |
| 行政・金融取引・健康 | 該当なし |
| カテゴリ | 教育 |
| 連絡先 | gcp.demo.776@gmail.com / https://thai-memo-prod.web.app |
| 価格 | 無料（サブスク: premium_monthly / premium_annual、各 1 週間の無料トライアルあり） |

### データセーフティ

- 共有なし。送信時は暗号化。アカウント削除 URL: https://thai-memo-prod.web.app/account-deletion.html
- 収集（すべて必須・一時処理ではない）

| データ | 目的 |
|---|---|
| 名前・メールアドレス | アプリの機能、アカウント管理 |
| ユーザー ID | アプリの機能、分析、アカウント管理 |
| 購入履歴 | アプリの機能 |
| その他のアプリ内メッセージ（お問い合わせ） | アプリの機能 |
| アプリのインタラクション数 | 分析 |
| その他の操作（学習データ） | アプリの機能、カスタマイズ |
| デバイスまたはその他の ID（FCM トークン等） | アプリの機能、分析 |
| クラッシュログ（Crashlytics）※未申告 | 分析 |
| その他のアプリのパフォーマンス データ（Crashlytics の非致命的エラー）※未申告 | 分析 |

- 発音練習の録音は端末内処理のため申告しない（Android は OS の SpeechRecognizer を使う）

## ストア掲載情報（ja-JP）

- アプリ名: まいにちタイ語 - 毎日の例文で単語が増える
- 簡単な説明: 今の語彙に合ったタイ語例文で、読める表現を毎日少しずつ。声調をその場で判定し、クイズで復習。旅行やBLドラマなど11テーマ。
- 詳しい説明: App Store（ja）の説明文と同じ
- 画像: `build/store_shots/out/android/`（`flutter test test/screenshots/store_mock_screens.dart` → `flutter test test/screenshots/store_screenshots.dart --dart-define=DEVICE=android`）
