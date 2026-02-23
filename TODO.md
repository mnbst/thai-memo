# Thai Memo - TODO

## 機能

- 声調指定で例文生成
- 1日1件の例文生成を自動化（通知トリガーで自動生成）

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

## 穴埋めクイズ機能

### 概要
過去に生成した例文から毎日5問の穴埋め問題を自動生成。間隔反復（SRS）で記憶定着を最大化し、通算正答率を表示してゲーム感覚で復習できる。
現在の復習の表示内容を完全に書き換える

### 仕様
- 深夜バッチで過去の例文から5件を選び、Geminiで穴埋め問題を生成
- 例文中の1単語を空欄にし、4択の選択肢を提示
- 正解時にはアニメーション表示、不正解時には正解と解説を表示
- 通算正答率・連続正解数をクイズ画面上部に表示

### SRS（間隔反復）による出題ロジック

5問の内訳を以下の優先順で選出:

| 優先度 | 対象 | 説明 |
|--------|------|------|
| 1 | 1日前の例文 | 新規学習の初回復習（必ず1問以上） |
| 2 | 3日前の例文 | 2回目の復習 |
| 3 | 7日前の例文 | 3回目の復習 |
| 4 | 30日前の例文 | 長期記憶の確認 |
| 5 | 過去に不正解だった例文 | 弱点補強（正答率が低い順） |
| 6 | ランダム | 上記で5問に満たない場合に補充 |

- 各間隔の対象日は±1日の幅を持たせる（例: 3日前 = 2〜4日前）
- 同じ例文が同日に重複出題されないようにする
- 例文のストックが少ない初期段階ではランダム補充で5問を確保
- 生成した例文が5問以下なら生成した分だけ

### データ設計

```
// Firestore（バッチ生成）
quiz_queue/{docId}
  ├── uid: string
  ├── scheduled_date: string         // 配信日
  ├── questions: array               // 5問分
  │   ├── sentence_id: string        // 元の例文ID
  │   ├── thai_text: string          // 元の完全な例文
  │   ├── blank_text: string         // 空欄入り例文（___で表示）
  │   ├── correct_answer: string     // 正解の単語
  │   ├── choices: string[]          // 4択（正解含む、シャッフル済み）
  │   ├── pronunciation: string      // 正解単語の発音
  │   ├── explanation: string        // 解説（なぜその単語が入るか）
  │   └── srs_interval: number       // この問題のSRS間隔（1/3/7/30/0=弱点/random）
  └── sent: boolean

// Firestore（回答結果をサーバー側にも保存 → SRS選出に使用）
users/{uid}/quiz_answers/{docId}
  ├── sentence_id: string
  ├── is_correct: boolean
  ├── answered_at: timestamp

// SQLite（ローカル）
quiz_results テーブル
  ├── id: INTEGER PRIMARY KEY
  ├── sentence_id: TEXT
  ├── question_date: TEXT            // 出題日
  ├── is_correct: INTEGER            // 0 or 1
  ├── selected_answer: TEXT
  ├── correct_answer: TEXT
  └── answered_at: TEXT

quiz_stats テーブル（集計キャッシュ）
  ├── total_answered: INTEGER
  ├── total_correct: INTEGER
  ├── current_streak: INTEGER        // 連続正解数
  ├── best_streak: INTEGER           // 最高連続正解数
  └── updated_at: TEXT
```

### 実装タスク

#### Phase Q1: バッチ問題生成（Cloud Functions）
- [ ] SRS間隔（1/3/7/30日前）に基づく例文選出ロジック
- [ ] 不正解履歴（quiz_answers）から弱点例文を優先選出
- [ ] Geminiで穴埋め問題（空欄・4択・解説）を生成
- [ ] quiz_queueに保存、復習通知と同時に配信

#### Phase Q2: Flutter側クイズUI
- [ ] クイズ画面（1問ずつ表示、4択ボタン、正解/不正解フィードバック）
- [ ] 結果サマリー画面（5問終了後に正答数・通算正答率を表示）
- [ ] ボトムナビにクイズタブ追加 or 復習タブ内にクイズセクション追加

#### Phase Q3: 成績管理・回答同期
- [ ] quiz_results / quiz_stats テーブル作成（SQLite）
- [ ] 正答率・連続正解数の計算ロジック
- [ ] 回答結果をFirestore（quiz_answers）に同期（SRSバッチ用）
- [ ] 成績表示UI（通算正答率、連続正解数、最高記録）

## マイルストーン

- **v1.0** (現在): Freeプランのみ、基本機能
- **v1.1**: ランク管理基盤 + シチュエーション拡張
- **v1.2**: Premiumプラン機能実装
- **v1.3**: 課金・サブスクリプション統合
- **v2.0**: Proプラン + 全機能リリース
