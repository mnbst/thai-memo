# Thai Memo - TODO

## 会員ランク機能の実装計画

### 現状（Freeプラン）
- [x] 1日1回の文生成（24時間バックグラウンド生成）
- [x] Gemini 2.5 Flash モデル
- [x] 基本的な16シチュエーション
- [x] タイ語文10〜15単語
- [x] 単語分解最大15単語
- [x] contextフィールド（50文字以内）

### Premiumプラン（未実装）
- [ ] 1日3〜5回の文生成
- [ ] 拡張シチュエーション（30〜40種類）
  - ビジネス詳細（会議、プレゼン、商談など）
  - 医療詳細（診察、症状説明、薬の説明など）
  - 教育（教える、学ぶ、試験など）
  - エンターテイメント（映画、コンサート、観光など）
  - その他日常生活の細分化
- [ ] タイ語文15〜20単語
- [ ] 単語分解最大20単語
- [ ] contextフィールド（100文字以内）
- [ ] 追加情報フィールド
  - 類義表現（similar_expressions）
  - よくある間違い（common_mistakes）
  - 上級者向けバリエーション（advanced_variations）

### Proプラン（未実装）
- [ ] 無制限の文生成
- [ ] Gemini 2.5 Pro モデル
- [ ] カスタムシチュエーション（ユーザー指定）
- [ ] タイ語文20〜30単語（長文対応）
- [ ] 単語分解最大30単語
- [ ] contextフィールド（制限なし）
- [ ] 全ての追加情報フィールド
- [ ] 音声読み上げ用データ（phonetic_breakdown）
- [ ] 会話例（conversation_examples）
- [ ] 関連語彙リスト（related_vocabulary）

## 実装タスク

### Phase 1: ランク管理基盤
- [ ] ユーザーランク管理テーブル追加（SQLite）
- [ ] Firebase Auth Custom Claims でランク情報管理
- [ ] ランク判定ロジック実装（Cloud Functions）
- [ ] ランク別設定ファイル作成（`functions/src/config/rankConfigs.ts`）

### Phase 2: シチュエーション拡張
- [ ] 拡張シチュエーションリスト作成
- [ ] ランク別シチュエーション管理
- [ ] UI：シチュエーション選択画面実装
- [ ] 選択履歴の保存・表示

### Phase 3: 出力内容の拡張
- [ ] データモデル拡張（ThaiSentence型）
  - similar_expressions: string[]
  - common_mistakes: string
  - advanced_variations: string[]
  - phonetic_breakdown: object
  - conversation_examples: object[]
  - related_vocabulary: object[]
- [ ] DB スキーマ拡張（新規テーブルまたはJSON列）
- [ ] Gemini プロンプト調整（ランク別）
- [ ] UI：拡張情報表示画面

### Phase 4: 課金・サブスクリプション
- [ ] RevenueCat または Stripe 統合
- [ ] 課金プラン設定
- [ ] App Store / Google Play 課金設定
- [ ] 購入フロー実装
- [ ] ランクアップグレード処理
- [ ] レシート検証（Cloud Functions）

### Phase 5: レート制限・クォータ管理
- [ ] 日次生成回数制限実装
- [ ] Firebase Firestore でクォータ管理
- [ ] クォータ超過時のUI表示
- [ ] リセットスケジュール（日次0時リセット）

## 技術的検討事項

### Cloud Functions
- [ ] ランク別Function分離 vs 単一Function + 分岐
  - 推奨: 単一Function + ランク判定（保守性）
- [ ] Gemini API コスト最適化
  - Flash vs Pro の使い分け
  - キャッシング戦略

### データベース
- [ ] 拡張情報の保存方法
  - Option A: JSON列に追加情報を格納
  - Option B: 新規テーブル（sentence_extensions）作成
- [ ] インデックス最適化（ランク別クエリ）

### UI/UX
- [ ] ランク別機能の見せ方
  - ロックアイコン + アップグレード誘導
  - 無料トライアル提供
- [ ] プレミアム機能のプレビュー

## マイルストーン

- **v1.0** (現在): Freeプランのみ、基本機能
- **v1.1**: ランク管理基盤 + シチュエーション拡張
- **v1.2**: Premiumプラン機能実装
- **v1.3**: 課金・サブスクリプション統合
- **v2.0**: Proプラン + 全機能リリース
