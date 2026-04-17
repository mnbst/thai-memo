# クイズ生成ロジック

## 概要

ユーザーの学習済み例文からSRS（間隔反復）アルゴリズムで復習対象を選出し、
OpenAIで穴埋め4択クイズを生成する（`generateQuiz` Cloud Function）。

## 処理フロー

```
クライアント (onCall)
    ↓
① 認証チェック + 日次クォータチェック (remaining_quizzes > 0)
    ↓
② SRS に基づく復習対象例文の選出（最大3文）
    ↓
③ デフォルト例文やユーザー例文で補填し、最大5問分の生成元を確定
    ↓
④ 最大5問分の生成元をまとめて OpenAI に投げてクイズ生成
    ↓
⑤ 生成失敗分だけまとめて1回リトライ
    ↓
⑥ クォータデクリメント（トランザクション）
```

## ① クォータチェック

| ティア | 1日の上限 |
|--------|-----------|
| free | 2回/日 |
| premium | 10回/日 |

`dailyBatch`（JS側）が毎晩 JST 基準でリセット。

## ② SRS 例文選出 — `selectSentencesBySRS`

選出の優先順位:

### ① SRS 間隔マッチ（最大3枠）

`SRS_DAYS = [1, 3, 7, 14, 30]` からランダムに3間隔を選び、
各間隔で「経過日数が `interval ± 1日` の範囲にある例文」の中から
UVM P値が最低の文を1つ選出する。

```
経過日数 = floor((今 - created_at) / 86400秒)  ※JST基準
```

### ② SRS 対象外のユーザー例文で補充

①で埋まらなかった枠を、残りの全ユーザー例文から P値が低い順に補充。

### ③ デフォルト例文で不足分を補充

それでも不足する場合、`DEFAULT_SENTENCES` から `estimated_vocab ± FREQ_BAND_HALF(10)` 帯域内に絞り、effective P が低い順に補充する。
この段階の選出は復習枠の最大3文までで、残りは OpenAI 呼び出し前の生成元補填で追加する。

### UVM P値の取得

ユーザーの全例文の `key_word` とデフォルト例文の `key_word` を一括して
`users/{uid}/uvm/{word}` から `db.getAll()` で取得。UVM未登録語は `UNKNOWN_WORD_P = 0.3` を使用。

## ③ 例文が0件の場合

初回登録直後などユーザー例文がない場合は `generateFromDefaults` へ分岐。
`DEFAULT_SENTENCES` を帯域フィルタ → effective P 昇順 → `estimated_vocab` 近傍の順に5問選出。

## ④ クイズ一括生成 — `generateQuestionsFromSources`

SRS選出分にデフォルト例文、必要に応じてユーザー例文を補填し、最大5問分の生成元を先に確定する。
確定した複数例文をまとめて `OpenAiQuizService.generateQuizQuestions()` に渡し、JSON の `questions` 配列として受け取る。
各問題には内部対応付け用の `source_index` を出力させ、元例文の `sentence_id` / `srs_interval` を付与してからクライアントへ返す。

**source_index / key_word バリデーション**:
`source_index` が範囲外または重複している問題はドロップする。
`key_word` が指定されている場合、`correct_answer` が `key_word` と一致するか確認。
欠落・サニタイズ除外・`key_word` 不一致の例文だけをまとめて1回リトライし、それでも失敗したものはスキップする。

**コスト検証ログ**:
OpenAI の `usage` が返る場合、`OpenAI token usage` ログに `requestMode`、`sentenceCount`、`inputTokens`、`outputTokens`、`reasoningTokens`、`costUsd` を出力する。
一括生成の検証では `requestMode: "batch"` のログを見る。

### OpenAI プロンプト — `quizGenerationService.ts`

```
- source_index には入力IDを入れる
- ヒントなし画面では `blank_text` と `choices` のタイ語だけが表示される前提で、周辺タイ語だけから正解が一意に判断できる問題にする
- 【穴埋め対象】が指定されている場合、必ずその単語を___ に置き換える
- 4択（正解1つ＋紛らわしいダミー3つ）
- choices・correct_answer はタイ語表記の単語のみ
- 「俺/私」「あなた/君」「彼/彼女」などの訳語・話者性別・敬意・人称知識だけで区別する選択肢は、周辺タイ語に明確な手がかりがない限り使わない
- explanation は日本語で簡潔に
- ダミーは空欄に入れた完成文が、前後語・文法・品詞・項構造のどれかで明確に破綻する語だけを使う
- 位置詞・方位詞・前置詞などの機能語が正解の場合、同じ文法枠で自然な別解になる語をダミーにしない
- 「元の文と合わない」「日本語訳と違う」「文脈に合わない」「意味が変わる」だけを不正解理由にするのは禁止
```

- max_output_tokens: 4096
- Structured Outputs の JSON Schema で JSON 形式を強制

### サニタイズ — `sanitizeQuizQuestion`

1. `correct_answer` がタイ語文字（`\u0E00-\u0E7F`）でなければ問題をドロップ
2. `choices` からタイ語以外（日本語・英語・ラテン文字）を除外
3. 4択に満たなければ問題をドロップ（未検証の単語プールから補充しない）
4. `dummy_reasons` が3つの不正解選択肢それぞれに対応しているか確認
5. 不正解理由が元文・日本語訳・文脈差分だけに依存している場合、問題をドロップしてリトライ対象にする

## ⑤ 生成元の事前補填 — `buildQuizSourcesForGeneration`

SRS選出分の `sentence_id` を除外したうえで、帯域内デフォルト例文から
effective P 昇順に最大5問まで補填する。
デフォルト例文で足りない場合のみ、ユーザー例文を UVM P値昇順で追加する。
補填は OpenAI 呼び出し前に完了するため、通常時の LLM 呼び出しは `sentenceCount: 5` の1回になる。

## ⑥ クォータデクリメント

Firestoreトランザクションで `remaining_quizzes` をアトミックに -1。
クォータが 0 以下なら `resource-exhausted` エラーを throw。

## データ構造

生成されるクイズ問題（`QuizQuestion`）:

| フィールド | 内容 |
|-----------|------|
| `sentence_id` | 元例文のFirestore ID |
| `thai_text` | 元のタイ語文 |
| `blank_text` | 穴埋め（`___`）付きタイ語文 |
| `correct_answer` | 正解単語（タイ語）|
| `choices` | 4択（シャッフル済み）|
| `pronunciation` | 正解単語の発音 |
| `explanation` | 日本語解説 |
| `srs_interval` | 選出時のSRS間隔（-1: SRS外、0: デフォルト、1/3/7/14/30: 日数）|
| `japanese_translation` | 例文の日本語訳 |
| `sentence_pronunciation` | 例文全体の発音 |
