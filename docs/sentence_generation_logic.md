# 例文生成ロジック

## 概要

ユーザーの語彙レベル（UVM）に合わせたタイ語例文をGemini AIで生成する。
単発生成（`generateThaiSentence`）とバッチ生成（`generateBatchSentences`）の2モードがある。

## 処理フロー

```
クライアント (onCall)
    ↓
① 認証チェック + クォータチェック (remaining_sentences > 0)
    ↓
② ターゲット単語選定 (UVM × embedding)
    ↓
③ プロンプト構築 (estimated_vocab → 難易度)
    ↓
④ Gemini API 呼び出し（JSON応答, exponential backoff）
    ↓
⑤ NLP 後処理（音節分割・品詞・発音）
    ↓
⑥ ターゲット単語の含有検証（失敗時リトライ×1）
    ↓
⑦ Firestore 保存 + クォータデクリメント（トランザクション）
    ↓
⑧ UVM 露出登録（キーワード=新規作成あり、非キーワード未登録=スキップ）+ estimated_vocab 同期
```

## ① クォータチェック

| ティア | 1日の上限 |
|--------|-----------|
| free   | `remaining_sentences` フィールドで管理（`dailyBatch` が毎晩リセット） |
| premium | 同上（上限値が異なる） |

freeユーザーは初回からfreeスペックで生成する。過去の `is_first_generation` フラグが残っていてもpremiumスペックにはしない。

## ② ターゲット単語選定 — `select_uvm_target_words` (`sentence_service.py:62`)

1. GCSから `freq_rank_top10000.json` を読み込み（メモリキャッシュ済み）
2. `get_session_words(db, uid, freq_rank, ...)` (uvm.py) でUVMから単語を選定
   - `estimated_vocab ± FREQ_BAND_HALF` の帯域内から P(know) が低い単語を優先
   - topicが未指定の場合はembeddingで最適テーマを選択
3. free ティアは `max_vocab = FREE_TIER_MAX_VOCAB (100)` にキャップ

バッチ生成では `count` 分の単語を一括選定し、各単語に embedding でテーマを割り当て。
重複テーマが出た場合は別テーマに差し替えて多様性を確保する。

## ③ プロンプト構築 — `build_uvm_prompt` (`prompts.py`)

`estimated_vocab` から難易度ラベルを決定:

| estimated_vocab | ラベル | 文長 |
|-----------------|--------|------|
| 0-99 | 入門 | 〜7単語 |
| 100-299 | 初級 | 〜7-8単語 |
| 300-599 | 初中級 | 〜8-10単語 |
| 600-1499 | 中級 | 〜10-16単語 |
| 1500以上 | 上級 | 自然な長さ |

ターゲット単語がある場合は「最優先で含めること」として指示し、テーマ/文体/文法などは「できれば反映」の補助扱いにする。

テーマはクライアントから送られない（free/premium ともサーバー自動選出）。候補プールは共通で
`TOPIC_MIN_VOCAB` によるレベル別ゲートのみ。選び方だけが tier で違い、free は**一様抽選**、
premium は embedding で key_word に最も近いテーマを選ぶ。free で embedding を使うと
テーマ embedding の重心バイアスで BLドラマに偏る（2026-08-14 実測 82.7%）。
free では BLドラマだけ語彙ゲートの外で `FREE_BL_TOPIC_RATE`（10%）の固定枠を持つ。スタイルは `FREE_STYLES` に制限し、`grammarFocus` は使わない。
語彙スコアごとの topic / style / grammarFocus 解禁仕様は `docs/vocab_unlock_parameters.md` を参照。

プロンプトでは `word_breakdown` を最大20単語までに制限する。
`context.usage_scenarios` と `context.cultural_notes` は各50文字以内の簡潔な補足にする。

## ④ Gemini API 呼び出し

- モデル: premium → `GEMINI_MODEL_PREMIUM`、free → `GEMINI_MODEL`
- temperature: `API_TEMPERATURE`
- `response_schema = RESPONSE_SCHEMA`（`constants.py` 定義）で JSON 形式を強制
- 一時エラー (503/429) 時は最大3回 exponential backoff リトライ

バッチ生成は `asyncio.gather` で全文を並列生成（`_generate_batch_async`）。

## ⑤ NLP 後処理 — `enrich_with_nlp` (`nlp.py`)

PyThaiNLP を使用して各単語に以下を付与:
- 音節分割
- 発音（ローマ字、声調記号付き）
- 品詞タグ（日本語ラベル）

## ⑥ ターゲット単語の含有検証

`thai_text` または `word_breakdown[].word` にターゲット単語が含まれているか確認。
含まれていない単語がある場合は不足単語を明示したプロンプトで再生成（最大1回）。
リトライ後も不足する場合はそのまま返す（生成成功扱い）。

## ⑦ Firestore 保存

`users/{uid}/sentences/{auto-id}` に保存。フィールド:

```
thai_text, pronunciation, japanese_translation, created_at, key_word
```

`remaining_sentences` のデクリメントとドキュメント書き込みはトランザクションでアトミックに実行。
クォータが足りなければ `QUOTA_EXCEEDED` をthrowしてロールバック。

## ⑧ UVM 更新

`_register_sentence_exposure` (`sentence_handlers.py:78`) が以下の2段階で `register_exposure` を呼ぶ:

1. **キーワード** (`exposed_words`): `target_words=target_words` 付きで呼ぶ
   - UVM登録済み → P を ALPHA_EXPOSURE(0.03) 分微増
   - UVM未登録 → 新規ドキュメントを作成（P=NEW_WORD_P=0.1）
2. **キーワード以外** (`other_words`): `target_words` なしで呼ぶ
   - UVM登録済み → P を ALPHA_EXPOSURE(0.03) 分微増
   - UVM未登録 → **スキップ**（新規作成しない）

未登録の非キーワード語をスキップするのは意図的な設計（`target_words=None` を渡すことで制御）。
そのため、非キーワード語として例文に何度登場しても UVM に記録されず、ギャップスキャンで「未習得」と判定され続ける場合がある。

3. **estimated_vocab 同期** `sync_estimated_vocab`: P値分布から語彙境界 rank を再計算し `users/{uid}.estimated_vocab` を更新（詳細は `docs/estimated_vocab_logic.md`）

## バッチ生成の特記事項

`generateBatchSentences` は残クォータ全量を一度に生成する。
全文の生成が完了してから1つのトランザクションでまとめてFirestoreに書き込む。
生成失敗したインデックスはスキップされ、成功分のみ保存される。
