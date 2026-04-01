# クイズ生成ロジック

## 概要

ユーザーの学習済み例文からSRS（間隔反復）アルゴリズムで復習対象を選出し、
Gemini AIで穴埋め4択クイズを生成する（`generateQuiz` Cloud Function）。

## 処理フロー

```
クライアント (onCall)
    ↓
① 認証チェック + 日次クォータチェック (remaining_quizzes > 0)
    ↓
② SRS に基づく復習対象例文の選出（最大3文）
    ↓
③ ランダムシャッフルして最大5問抽出
    ↓
④ 各例文を並列で Gemini API に投げてクイズ1問ずつ生成
    ↓
⑤ 5問未満の場合はデフォルト例文で補填
    ↓
⑥ クォータデクリメント（トランザクション）
```

## ① クォータチェック

| ティア | 1日の上限 |
|--------|-----------|
| free | 2回/日 |
| premium | 10回/日 |

`dailyBatch`（JS側）が毎晩 JST 基準でリセット。

## ② SRS 例文選出 — `selectSentencesBySRS` (`generateQuiz.ts:415`)

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

### UVM P値の取得

ユーザーの全例文の `key_word` とデフォルト例文の `key_word` を一括して
`users/{uid}/uvm/{word}` から `db.getAll()` で取得。UVM未登録語は `UNKNOWN_WORD_P = 0.3` を使用。

## ③ 例文が0件の場合

初回登録直後などユーザー例文がない場合は `generateFromDefaults` へ分岐。
`DEFAULT_SENTENCES` を帯域フィルタ → effective P 昇順 → `estimated_vocab` 近傍の順に5問選出。

## ④ クイズ1問生成 — `generateSingleQuiz` (`generateQuiz.ts:324`)

各例文に対して `GeminiService.generateQuizQuestions()` を呼び出し1問生成。

**key_word バリデーション**:
`key_word` が指定されている場合、`correct_answer` が `key_word` と一致するか確認。
不一致時は1回リトライ。それでも不一致なら null を返してスキップ。

### Gemini プロンプト (`geminiService.ts:137`)

```
- 【穴埋め対象】が指定されている場合、必ずその単語を___ に置き換える
- 4択（正解1つ＋紛らわしいダミー3つ）
- choices・correct_answer はタイ語表記の単語のみ
- explanation は日本語で簡潔に
```

- temperature: 0.8、maxOutputTokens: 4096
- `responseSchema` で JSON 形式を強制

### サニタイズ — `sanitizeQuizQuestion` (`geminiService.ts:196`)

1. `correct_answer` がタイ語文字（`\u0E00-\u0E7F`）でなければ問題をドロップ
2. `choices` からタイ語以外（日本語・英語・ラテン文字）を除外
3. 不足分をシード単語プール（`word_breakdown` の単語群）から補充
4. 4択に満たなければ問題をドロップ

## ⑤ デフォルト例文による補填 — `fillWithDefaults` (`generateQuiz.ts:221`)

生成済み問題の `sentence_id` を除外したうえで、帯域内デフォルト例文から
effective P 昇順に選出し、Gemini で追加生成する。
補填生成が失敗しても既存の問題のみで返す（部分的成功を許容）。

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
