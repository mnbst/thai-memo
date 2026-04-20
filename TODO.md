# TODO

## 学習ロジック / UVM

- [ ] クイズ難易度を下げる機能の検討
  - 背景: ギャップ語（rank < estimated_vocab-30）でクイズ不正解が続くとP=0に戻りStep 1に居続け、フロンティア帯（Step 2）が選ばれず estimated_vocab が上昇しにくくなる
  - 対策候補: 選択肢を減らす / ヒント表示 / 出題頻度を下げて帯域語を混ぜる

## 例文生成 / 品質

- [ ] Premium+ プラン向けに例文品質を底上げする
  - モデル: Gemini 2.5 Flash（現行と同じ）
  - 変更: `thinking_budget` を無制限（-1）に設定
  - Premium / 無料は現状維持（thinking_budget=256）
  - 影響: thoughts トークンが output 課金（$2.50/1M）に乗るのでコスト試算を更新する

## 分析 / 可視化

- [ ] ユーザーごとの語彙スコア（estimated_vocab）の日次推移を記録・可視化
  - `dailyBatch` で各ユーザーの `estimated_vocab` を `users/{uid}/vocab_history/{YYYY-MM-DD}` に書き込む
  - または BigQuery Export（Firestore → BigQuery）でまとめて集計
  - ユーザー数が増えてから対応
