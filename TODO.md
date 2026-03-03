# Thai Memo - TODO

## 機能

- 声調指定で例文生成
- 1日1件の例文生成を自動化（通知トリガーで自動生成）

## プラン構成・料金

### 料金（確定）
- 月額: ¥1,000
- 年額: ¥7,800（35%割引、月額¥650相当）

### Free vs Premium 機能比較

| 機能 | Free | Premium |
|------|------|---------|
| 例文生成 | 1日5回（プールから配信） | 1日10回（リアルタイム生成） |
| クイズ | 1日1回 | 1日10回 |
| トピック | 4種 | 16種 |
| 文体 | 2種 | 5種 |
| 出力パラメータ設定 | × | ○ |
| 広告 | あり | なし |

### AIモデル構成（確定）
- 例文生成（プレミアム）: gemini-2.5-flash（品質重視）
- 例文生成（無料プール）: gemini-2.5-flash-lite
- クイズ生成: gemini-2.5-flash-lite

### コスト試算（プレミアム・最大利用時）
- 例文(flash): $0.0094/回 × 10回/日 × 30日 = $2.82
- クイズ(lite): $0.0014/回 × 10回/日 × 30日 = $0.42
- 月間合計: $3.25（≒¥488）
- 収入: ¥1,000 × 70%（Apple手数料後） = ¥700
- 利益: +¥212/月

### 課金基盤（実装済み）
- [x] RevenueCat統合（purchases_flutter）
- [x] Paywall画面
- [x] サブスク状態管理（subscription_provider）
- [x] 広告表示制御（ad_provider / AdMob）
- [x] Firestore quota管理（日次リセット）
- [ ] RevenueCat APIキー設定（本番用）
- [ ] App Store Connect サブスク商品登録
- [ ] Google Play Console サブスク商品登録
- [ ] RevenueCat Webhook設定（Firestore tier同期）

## 穴埋めクイズ機能

### 概要
過去に生成した例文から毎日5問の穴埋め問題を自動生成。間隔反復（SRS）で記憶定着を最大化し、通算正答率を表示してゲーム感覚で復習できる。
現在の復習機能を完全に入れ替え

### 仕様
- 深夜バッチで過去の例文から5件を選び、Geminiで穴埋め問題を生成
- 例文中の1単語を空欄にし、4択の選択肢を提示
- 正解時にはアニメーション表示、不正解時には正解と解説（簡潔に）を表示
- 通算正答率をクイズ画面上部に表示

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

- **v1.0** (リリース済み): Free版、基本機能
- **v1.1** (実装中): Premium機能 + RevenueCat課金基盤
- **v1.2**: App Store/Google Play サブスク商品登録・リリース
