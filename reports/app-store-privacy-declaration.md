# App Store Connect プライバシー申告チェックリスト

**生成日時**: 2026-02-14
**アプリ名**: Thai Memo
**バージョン**: 1.0.0

---

## はじめに

このドキュメントは、App Store Connectで「App Privacy」セクションを入力する際のガイドです。Appleの最新要件（2024-2026）に基づいて作成されています。

**重要**: このチェックリストは正確な情報提供を目的としていますが、App Store Connectでの申告時には必ず最新の要件を確認してください。

---

## セクション1: データ収集の概要

### Does this app collect data?
**回答**: **Yes**

**理由**: Firebase匿名認証でユーザーIDを収集

---

## セクション2: データタイプ別申告

### 📋 収集するデータ

#### 1. Identifiers（識別子）

##### User ID
- **収集**: ✅ Yes
- **リンク状態**: **Linked to User**
- **トラッキング**: ❌ No
- **目的**:
  - [x] App Functionality
- **詳細**: Firebase Anonymous User ID (UID)

##### Device ID
- **収集**: ❌ No

---

#### 2. Usage Data（使用状況データ）

##### Product Interaction
- **収集**: ✅ Yes
- **リンク状態**: **Linked to User**
- **トラッキング**: ❌ No
- **目的**:
  - [x] App Functionality
- **詳細**: 例文生成日時、お気に入り登録、学習履歴（すべてローカル保存）

---

#### 3. Diagnostics（診断データ）

##### Crash Data
- **収集**: ✅ Yes
- **リンク状態**: **Linked to User**
- **トラッキング**: ❌ No
- **目的**:
  - [x] App Functionality
  - [x] Analytics
- **詳細**: Firebase Crashlyticsによるクラッシュレポート（将来実装予定）

**注意**: 現在Crashlyticsは実装されていませんが、将来追加する可能性があるため申告を推奨します。実装しない場合は、この項目を削除してください。

##### Performance Data
- **収集**: ❌ No

---

#### 4. User Content（ユーザーコンテンツ）

##### Other User Content
- **収集**: ❌ No（ローカル保存のみ、収集・送信なし）

**重要**: 生成された例文はローカルデバイス上にのみ保存され、クラウドに送信されないため、「収集」とはみなされません。

---

### ❌ 収集しないデータ（すべて No）

以下のデータタイプはすべて **"No"** を選択してください：

#### Contact Info
- [ ] Name
- [ ] Email Address
- [ ] Phone Number
- [ ] Physical Address
- [ ] Other Contact Info

#### Health & Fitness
- [ ] Health
- [ ] Fitness

#### Financial Info
- [ ] Payment Info
- [ ] Credit Info
- [ ] Other Financial Info

#### Location
- [ ] Precise Location
- [ ] Coarse Location

#### Sensitive Info
- [ ] Sensitive Info（すべて）

#### Contacts
- [ ] Contacts

#### User Content
- [ ] Emails or Text Messages
- [ ] Photos or Videos
- [ ] Audio Data
- [ ] Gameplay Content
- [ ] Customer Support
- [ ] Other User Content ⚠️ ローカル保存のみなので "No"

#### Browsing History
- [ ] Browsing History

#### Search History
- [ ] Search History

#### Identifiers
- [x] User ID ✅ Firebase UID
- [ ] Device ID

#### Purchases
- [ ] Purchase History

#### Usage Data
- [x] Product Interaction ✅ 学習履歴
- [ ] Advertising Data
- [ ] Other Usage Data

#### Diagnostics
- [x] Crash Data ✅ 将来実装予定
- [ ] Performance Data
- [ ] Other Diagnostic Data

#### Other Data
- [ ] Other Data Types

---

## セクション3: データの使用目的

### 収集データごとの目的マッピング

| データタイプ | 目的カテゴリ | 詳細 |
|------------|------------|------|
| User ID (Firebase UID) | **App Functionality** | 認証管理、データ分離 |
| Product Interaction | **App Functionality** | 学習履歴管理、お気に入り機能 |
| Crash Data | **App Functionality**, **Analytics** | エラー診断、アプリ改善 |

### 目的カテゴリの定義

#### App Functionality
**説明**: アプリの中核機能を提供するため

**Thai Memoでの使用例**:
- Firebase匿名認証（ユーザー識別）
- 例文生成機能
- 学習履歴の保存と表示

#### Analytics
**説明**: アプリのパフォーマンスと使用状況を理解するため

**Thai Memoでの使用例**:
- クラッシュレポートの分析
- パフォーマンス最適化

#### 使用しない目的（すべて該当なし）
- ❌ Third-Party Advertising（広告なし）
- ❌ Developer's Advertising or Marketing（マーケティングなし）
- ❌ Product Personalization（パーソナライゼーションなし）

---

## セクション4: トラッキング

### Do you or your third-party partners use data from this app for tracking purposes?
**回答**: **No**

**理由**:
1. 広告を表示していない
2. 第三者データと連結していない
3. データブローカーと共有していない
4. クロスアプリ/クロスサイトトラッキングなし

**App Tracking Transparency (ATT)**: 不要

---

## セクション5: 第三者SDK

### 使用している第三者SDK

#### 1. Firebase Authentication
- **目的**: 匿名認証
- **データ収集**: User ID (UID)
- **プライバシーポリシー**: https://firebase.google.com/support/privacy

#### 2. Firebase Cloud Functions
- **目的**: バックエンドAPI
- **データ収集**: User ID (UID)、リクエストメタデータ
- **プライバシーポリシー**: https://firebase.google.com/support/privacy

#### 3. Google Generative AI (Gemini)
- **目的**: タイ語例文生成
- **データ収集**: シチュエーション情報（個人情報なし）
- **プライバシーポリシー**: https://policies.google.com/privacy

#### 4. Flutter Local Notifications
- **目的**: ローカル通知
- **データ収集**: なし（ローカル処理のみ）

#### 5. WorkManager
- **目的**: バックグラウンドタスク
- **データ収集**: なし（ローカル処理のみ）

#### 6. Flutter Secure Storage
- **目的**: セキュアなデータ保存
- **データ収集**: なし（ローカル処理のみ）

---

## セクション6: プライバシープラクティスの詳細説明

### 「Learn More」リンク用テキスト

以下のテキストをApp Store Connectの「Privacy Policy URL」フィールドに記載：

```
Thai Memoは、ユーザーのプライバシーを尊重し、最小限のデータ収集を行います。

【収集するデータ】
- Firebase匿名ユーザーID（認証用）
- 学習履歴（ローカル保存のみ）

【収集しないデータ】
- 氏名、メールアドレスなどの個人情報
- 位置情報
- 広告識別子（IDFA）

【AI使用の透明性】
- Google Gemini AIを使用してタイ語例文を生成
- 個人情報はAIに送信されません
- シチュエーション情報のみを送信

詳細: https://thaimemo.app/privacy
```

---

## セクション7: GDPR / CCPA 準拠

### GDPR（EU一般データ保護規則）

#### 法的根拠
- **契約の履行**: アプリサービスの提供
- **正当な利益**: アプリの改善、セキュリティ確保

#### ユーザー権利への対応
| 権利 | Thai Memoでの対応 |
|------|------------------|
| アクセス権 | アプリ内で学習履歴を閲覧可能 |
| 訂正権 | 例文の削除・再生成機能 |
| 削除権 | アプリ内削除機能、アンインストール |
| 制限権 | 通知のオプトアウト |
| ポータビリティ権 | 将来のエクスポート機能（計画中）|
| 異議権 | データ収集への異議申し立て対応 |

### CCPA（カリフォルニア州消費者プライバシー法）

#### 申告内容
- **個人情報の販売**: なし
- **個人情報の共有（広告目的）**: なし
- **機密個人情報の使用**: なし

---

## セクション8: チェックリスト最終確認

### App Store Connect 入力前の確認事項

- [ ] **プライバシーポリシーURL準備完了**
  - 日本語版: `https://thaimemo.app/privacy/ja`
  - 英語版: `https://thaimemo.app/privacy/en`
  - ※ドメイン準備中の場合は、GitHub Pagesまたは一時URLを使用

- [ ] **データ収集の正確性確認**
  - Firebase UID のみ収集
  - ローカルデータは「収集」ではない
  - Gemini APIへの送信内容を確認

- [ ] **トラッキングの定義確認**
  - 広告なし
  - 第三者データ連結なし
  - データブローカーとの共有なし

- [ ] **第三者SDKのプライバシー確認**
  - Firebaseのプライバシーポリシー確認
  - Geminiのデータ処理方法確認

- [ ] **ユーザー権利への対応準備**
  - データ削除機能実装済み
  - プライバシーリクエストへの対応フロー確立

---

## セクション9: よくある質問（FAQ）

### Q1: 生成された例文は「収集」にあたりますか？
**A**: いいえ。ローカルデバイス上にのみ保存され、クラウドに送信されないため、Appleの定義では「収集」にあたりません。

### Q2: Gemini APIへのリクエストは「データ共有」ですか？
**A**: はい。ただし、個人情報は送信されません。「あいさつ」「食べ物」などのシチュエーションカテゴリのみです。プライバシーポリシーで明示する必要があります。

### Q3: Firebase匿名認証のUIDは「個人情報」ですか？
**A**: はい。匿名であってもユーザーを識別できるため、「User ID」として申告が必要です。

### Q4: 通知機能は申告が必要ですか？
**A**: ローカル通知（flutter_local_notifications）はデータ収集を行わないため、申告不要です。ただし、Info.plistでの権限説明は必須です。

### Q5: バックグラウンドタスクは申告が必要ですか？
**A**: WorkManagerはローカル処理のみなので、データ収集の申告は不要です。ただし、Info.plistでのバックグラウンドモード宣言は必須です。

---

## セクション10: App Store Connect 入力手順

### ステップバイステップガイド

#### 1. App Store Connect にログイン
https://appstoreconnect.apple.com/

#### 2. アプリを選択
- My Apps → Thai Memo

#### 3. App Privacy セクションに移動
- App Information → Privacy Policy URL
- **URL**: `https://thaimemo.app/privacy`（準備中）

#### 4. "Get Started" をクリック

#### 5. データ収集の質問に回答
**"Does this app collect data?"**
→ **Yes**

#### 6. データタイプを選択

##### Identifiers
- User ID: **Yes**
  - Linked to User: **Yes**
  - Tracking: **No**
  - Purpose: **App Functionality**

##### Usage Data
- Product Interaction: **Yes**
  - Linked to User: **Yes**
  - Tracking: **No**
  - Purpose: **App Functionality**

##### Diagnostics（将来実装予定の場合のみ）
- Crash Data: **Yes**
  - Linked to User: **Yes**
  - Tracking: **No**
  - Purpose: **App Functionality**, **Analytics**

#### 7. トラッキングの質問に回答
**"Do you or your third-party partners use data from this app for tracking?"**
→ **No**

#### 8. プライバシーポリシーURLを入力
**Privacy Policy URL**: `https://thaimemo.app/privacy`

#### 9. 確認と公開
- 入力内容を確認
- "Publish" をクリック

---

## セクション11: 監査とコンプライアンス

### 定期確認事項（アップデート時）

- [ ] 新しいデータ収集がないか確認
- [ ] 第三者SDKのアップデート確認
- [ ] プライバシーポリシーの更新が必要か確認
- [ ] GDPRコンプライアンスの維持
- [ ] CCPAコンプライアンスの維持

### ドキュメント保管

以下のドキュメントを保管してください：
1. プライバシーポリシー（日本語・英語）
2. App Store Connectの申告内容スクリーンショット
3. 第三者SDKのプライバシーポリシー
4. データフロー図
5. データ削除手順

---

## セクション12: 参考リンク

### Apple公式ドキュメント
- [App Privacy Details](https://developer.apple.com/app-store/app-privacy-details/)
- [App Store Review Guidelines - Privacy](https://developer.apple.com/app-store/review/guidelines/#privacy)
- [Privacy Manifest Files](https://developer.apple.com/documentation/bundleresources/privacy_manifest_files)

### 第三者サービス
- [Firebase Privacy](https://firebase.google.com/support/privacy)
- [Google Privacy Policy](https://policies.google.com/privacy)
- [Gemini API Terms](https://ai.google.dev/gemini-api/terms)

### 法的要件
- [GDPR（EU）](https://gdpr.eu/)
- [CCPA（カリフォルニア州）](https://oag.ca.gov/privacy/ccpa)
- [COPPA（米国）](https://www.ftc.gov/legal-library/browse/rules/childrens-online-privacy-protection-rule-coppa)

---

## まとめ

Thai Memoアプリは、**プライバシーファースト**の設計により、最小限のデータ収集を実現しています。

**主要ポイント**:
- ✅ 個人情報の収集なし（Firebase匿名UIDのみ）
- ✅ ローカルファースト（すべての学習データはデバイス上）
- ✅ トラッキングなし
- ✅ 広告なし
- ✅ GDPR / CCPA 準拠

App Store Connectでのプライバシー申告は、このチェックリストに従って正確に行ってください。

---

**作成者**: Claude Code
**最終更新**: 2026-02-14
