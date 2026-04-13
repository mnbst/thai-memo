# TODO

## 学習ロジック / UVM

- [ ] クイズ難易度を下げる機能の検討
  - 背景: ギャップ語（rank < estimated_vocab-30）でクイズ不正解が続くとP=0に戻りStep 1に居続け、フロンティア帯（Step 2）が選ばれず estimated_vocab が上昇しにくくなる
  - 対策候補: 選択肢を減らす / ヒント表示 / 出題頻度を下げて帯域語を混ぜる

## 分析 / 可視化

- [ ] ユーザーごとの推定語彙数（estimated_vocab）の日次推移を記録・可視化
  - `dailyBatch` で各ユーザーの `estimated_vocab` を `users/{uid}/vocab_history/{YYYY-MM-DD}` に書き込む
  - または BigQuery Export（Firestore → BigQuery）でまとめて集計
  - ユーザー数が増えてから対応
