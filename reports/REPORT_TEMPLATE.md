# App Store審査前 統合チェックレポート

> このファイルはテンプレートです。実際のレポートは `/appstore-pre-review-agent` 実行時に自動生成されます。

---

生成日時: YYYY-MM-DD HH:mm:ss
アプリ名: Thai Memo
バージョン: 1.0.0
ビルド番号: 1

---

## 🎯 総合評価

### 提出準備状況

- 🔴 **未準備** - 重大な問題あり、提出不可
- 🟡 **要修正** - 修正推奨項目あり
- 🟢 **準備完了** - App Store提出可能

**現在の状態**: [評価結果がここに表示されます]

### スコアカード

| チェック項目 | 状態 | 重大問題 | 警告 | 備考 |
|------------|------|---------|------|------|
| コード品質 | - | 0件 | 0件 | Phase 1 |
| プライバシー | - | 0件 | 0件 | Phase 2 |
| メタデータ | - | 0件 | 0件 | Phase 3 |
| 総合審査 | - | 0件 | 0件 | Phase 4 |
| **合計** | - | **0件** | **0件** | - |

---

## ⚠️ 重大な問題（即座に修正必須）

### 優先度: 緊急

> エージェント実行時に検出された重大な問題がここにリストされます

---

## 📋 修正推奨項目

### 優先度: 高

> 修正を強く推奨する項目がリストされます

### 優先度: 中

> 可能であれば修正すべき項目がリストされます

---

## ✅ 合格項目

> 問題のない項目がリストされます

---

## 📝 App Store Connect 提出チェックリスト

### 事前準備

- [ ] プライバシーポリシーをWeb公開
  * URL: ____________________
- [ ] スクリーンショット準備（5-8枚）
  * iPhone 6.7": 1290 x 2796 px
  * iPhone 6.5": 1242 x 2688 px
- [ ] アプリアイコン（1024x1024px）
- [ ] プレビュービデオ（オプション）

### App Store Connect 入力

#### 1. App Information

- [ ] アプリ名: "______________________" (30文字以内)
- [ ] サブタイトル: "______________________" (30文字以内)
- [ ] プライマリカテゴリ: Education
- [ ] セカンダリカテゴリ: Reference
- [ ] プライバシーポリシーURL: ____________________
- [ ] サポートURL: ____________________

#### 2. Pricing and Availability

- [ ] 価格: 無料
- [ ] 配信国: 日本、タイ、その他

#### 3. App Privacy（データ収集申告）

**データタイプ**:
- [ ] ユーザーコンテンツ
  * 学習用に入力したテキスト
  * 使用目的: アプリ機能、パーソナライゼーション
  * リンク先: はい（ユーザーIDとリンク）
  * トラッキング: いいえ

- [ ] 識別子
  * Firebase匿名UID
  * 使用目的: アプリ機能
  * リンク先: はい
  * トラッキング: いいえ

- [ ] 使用状況データ
  * アプリ利用状況
  * 使用目的: アプリ機能改善、分析
  * リンク先: いいえ
  * トラッキング: いいえ

**サードパーティとのデータ共有**:
- [ ] Google（Gemini API）
  * 目的: AI文章生成サービス提供のため
  * データタイプ: ユーザー入力テキスト

#### 4. Version Information

- [ ] 説明文（4000文字以内）
```
Thai Memoは、AI（Google Gemini）を活用したタイ語学習アプリです。

【主な機能】
・AI文章生成：学びたいテーマを入力すると、自然なタイ語文章を自動生成
・単語分解表示：各単語の意味と用法を詳しく解説
・学習履歴：過去に学習した内容を保存・復習
・定期通知：学習リマインダーで継続的な学習をサポート

【こんな方におすすめ】
・タイ語を基礎から学びたい方
・自然な表現を身につけたい方
・毎日コツコツ学習したい方

※このアプリはGoogle Gemini AIを使用して文章を生成します。
※生成される内容は教育目的であり、正確性を保証するものではありません。
```

- [ ] キーワード（100文字以内）
```
タイ語,学習,Thai,language,AI,education,sentence,vocabulary,daily,study,grammar,practice
```

- [ ] プロモーショナルテキスト（170文字以内）
```
AIで楽しくタイ語学習！毎日の通知で継続的に実力アップ。初心者から上級者まで、あなたのペースで学べます。
```

- [ ] スクリーンショット
  * 5-8枚アップロード完了

#### 5. Build

- [ ] ビルドバージョン: 1.0.0 (1)
- [ ] Export Compliance
  * 暗号化の使用: はい（HTTPS通信）
  * 免除該当: はい（標準的な暗号化のみ）
- [ ] Content Rights
  * サードパーティコンテンツ: なし
  * 権利保有: 確認済み

#### 6. Age Rating

- [ ] 年齢レーティング: 4+
- [ ] コンテンツ評価
  * 暴力: なし
  * 性的コンテンツ: なし
  * 言語: 教育的使用のみ
  * ギャンブル: なし

#### 7. Review Information

- [ ] 連絡先情報
  * 名前: ____________________
  * メールアドレス: ____________________
  * 電話番号: ____________________

- [ ] デモアカウント
  * 必要なし（認証は匿名）

- [ ] 審査メモ
```
このアプリはGoogle Gemini APIを使用してタイ語の文章を生成します。
AIが生成したコンテンツは教育目的であり、不適切なコンテンツが生成されないよう
プロンプトエンジニアリングで制御しています。

【技術スタック】
- Flutter (iOS/Android クロスプラットフォーム)
- Firebase Authentication（匿名認証）
- Google Generative AI (Gemini API)
- ローカル通知（学習リマインダー）

【プライバシー】
ユーザーが入力した学習テキストはGemini APIに送信されますが、
個人を特定できる情報は含まれません。生成された文章はデバイス内にのみ保存されます。
```

---

## 🚀 提出までのアクションプラン

### Phase 1: 重大問題の修正（所要時間: 推定XXX分）

```bash
# 具体的な修正手順がここに表示されます
```

### Phase 2: プライバシーポリシー公開（所要時間: 30分）

```bash
# GitHub Pagesまたは他のホスティングサービスで公開
git add docs/PRIVACY_POLICY_*.md
git commit -m "Add privacy policy for App Store"
git push origin main

# GitHub Settings > Pages で有効化
# URL取得後、App Store Connectに登録
```

### Phase 3: メタデータ入力（所要時間: 1時間）

1. App Store Connectにログイン
2. 上記チェックリストに従って全項目入力
3. スクリーンショット・アイコンをアップロード

### Phase 4: ビルド＆提出（所要時間: 30分）

```bash
# 1. クリーンビルド
flutter clean
flutter pub get

# 2. テスト実行（オプションだが推奨）
flutter test

# 3. リリースビルド
flutter build ios --release

# 4. Xcodeでアーカイブ
open ios/Runner.xcworkspace
# Product > Archive
# Distribute App > App Store Connect
# Upload
```

### Phase 5: 提出＆審査待ち

1. App Store Connectで提出ボタンをクリック
2. 審査待ち（通常24-48時間）
3. 審査結果を確認

---

## 📊 予想スケジュール

| ステップ | 所要時間 | 完了予定 |
|---------|---------|---------|
| コード修正 | XXX分 | - |
| ポリシー公開 | 30分 | - |
| メタデータ入力 | 1時間 | - |
| ビルド＆提出 | 30分 | - |
| **合計準備時間** | **約X時間** | - |
| 審査期間 | 24-48時間 | - |
| **総所要時間** | **約X日** | - |

---

## 💡 追加の推奨事項

### 1. TestFlight配信（オプション）

```bash
# 内部テスター向けに事前配信
# App Store Connect > TestFlight > Internal Testing
# テスターを追加 > ビルドを選択 > 配信開始
```

メリット:
- 本番環境での事前テスト
- ユーザーフィードバック収集
- クラッシュレポート確認

### 2. App Store最適化（ASO）

- [ ] キーワードリサーチツール使用
  * App Annie、Sensor Tower等
- [ ] 競合アプリ分析
- [ ] A/Bテスト用スクリーンショット準備
- [ ] ローカライゼーション（タイ語版の追加）

### 3. マーケティング準備

- [ ] プレスリリース作成
- [ ] SNS投稿計画
  * Twitter/X
  * Instagram
  * Facebook
- [ ] ランディングページ作成
- [ ] ユーザーサポート体制構築

### 4. モニタリング設定

- [ ] Firebase Crashlytics設定
- [ ] Firebase Analytics設定
- [ ] App Store Connectアラート設定
- [ ] ユーザーレビューモニタリング

---

## 📞 サポートリソース

### Apple公式

- [App Store Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [App Store Connect Help](https://help.apple.com/app-store-connect/)
- [Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/)

### コミュニティ

- [Apple Developer Forums](https://developer.apple.com/forums/)
- [Stack Overflow - iOS](https://stackoverflow.com/questions/tagged/ios)
- [Reddit r/iOSProgramming](https://www.reddit.com/r/iOSProgramming/)

### このプロジェクト

- [スキル使用ガイド](../docs/APPSTORE_SKILLS_GUIDE.md)
- [プライバシーポリシー](../docs/PRIVACY_POLICY_ja.md)
- Claude Codeでいつでも質問可能

---

## 🔄 次のステップ

### 修正完了後

```bash
# Claude Codeでエージェントを再実行
/appstore-pre-review-agent
```

### すべてクリアした場合

```bash
# ビルド＆提出
./scripts/run-appstore-review.sh
```

---

## 📈 進捗トラッキング

- [ ] Phase 1: コード品質チェック - 完了
- [ ] Phase 2: プライバシーコンプライアンス - 完了
- [ ] Phase 3: メタデータ最適化 - 完了
- [ ] Phase 4: 総合審査チェック - 完了
- [ ] すべての重大問題を修正
- [ ] すべての推奨項目を確認
- [ ] App Store Connect入力完了
- [ ] ビルド＆アップロード完了
- [ ] 審査提出完了

---

**レポート生成**: App Store Pre-Review Agent v1.0.0
**実行日時**: [エージェント実行時に自動入力]
**次回チェック推奨**: 修正完了後、または重要な変更時

---

## 📝 メモ欄

```
ここに修正作業のメモや特記事項を記入できます


```
