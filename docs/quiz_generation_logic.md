# クイズ生成ロジック

## 概要

ユーザーの学習済み例文からSRS（間隔反復）アルゴリズムで復習対象を選出し、
Geminiで穴埋め4択クイズを生成する（`generateQuiz` Cloud Function）。まとめ
クイズは従来どおり全問穴埋めとし、対応を明示した新クライアントの確認クイズ
（`generateLearningQuiz`）だけを単語の意味4択にする。

## 確認クイズの意味4択

- 例文を読んだ直後の1問確認クイズだけが対象。まとめクイズは全問穴埋めのまま。
- 選択肢は元の例文の `word_breakdown.meaning` から正解1件＋誤答3件を作る。
- 空・重複を除いて4件揃わなければ、その問題は穴埋めへフォールバックする。
- 正解・選択肢・元例文はルールベースで固定し、Geminiは単語自体の意味・
  ニュアンス・使い方だけを日本語140文字以内（英語80語以内）で書く。
  誤答理由・例文解説・新しい例文は生成しない。
- 出題語のローマ字は常に添える（ヒント段階に含めない）。読めない語は意味も
  思い出せず、出題が成立しないため。
- 回答前は元例文とヒントを隠す。結果は正解・不正解とも正解語と単語の解説だけを出し、
  直前に読んだばかりの元例文は再掲しない。
- `generateLearningQuiz` でクライアントが `supported_quiz_formats` に
  `meaning_choice` を含めた場合だけ返す。
  1.4.8以前を含む未宣言クライアントには、常に従来の穴埋めだけを返す。

## 単語解説のキャッシュ

意味4択でGeminiが作るのは `explanation` の1項目だけで、しかも内容は例文に
依存しない「その単語そのものの説明」なので、最初に生成したユーザーの結果を
全ユーザー共有のキャッシュに貯めて2人目以降で使い回す
（`functions/go/word_explanation_cache.go`）。

- 保存先は Firestore `word_explanations`。ドキュメントIDは
  「言語＋単語＋意味」のSHA-1。同じ語でも意味が違えば別エントリにする。
- ヒット時は Gemini を呼ばず、キャッシュした解説をルールベース合成と
  サニタイズに通して1問を組み立てる。検査に落ちたら通常どおりモデルへ回す。
- 保存に失敗してもクイズは成立するのでログだけ残す。解説が空なら保存しない。
- 穴埋めは対象外（ダミーと理由もモデルが作るため）。
- 目的はレイテンシと生成失敗の削減。1問あたりのモデル費用は $0.0003 程度で、
  全語（頻度上位9,543語）を事前生成しても $3 ほどなので費用面の効果は小さい。

## 処理フロー

```
クライアント (onCall)
    ↓
① 認証チェック + 日次クォータチェック (remaining_quizzes > 0)
    ↓
② SRS に基づく復習対象例文の選出（最大3文）+ UVMフィラーで最大5文に補充
    ↓
③ クォータを先行消費（トランザクション）
    ↓
④ 各例文ごとに Gemini を並列呼び出しでクイズ生成
    ↓
⑤ key_word不一致・生成失敗分だけ1回リトライ
    ↓
⑥ 全問失敗時はクォータをリストア
```

## ① クォータチェック

| ティア | 1日の上限 |
|--------|-----------|
| free | 1回/日 |
| premium | 5回/日 |

`dailyBatch`（JS側）が毎晩 JST 基準でリセット。

## ② SRS 例文選出 — `selectSentencesBySRS`

選出の優先順位:

### ① SRS 間隔マッチ（最大3枠）

`SRS_DAYS = [1, 3, 7, 14, 30]` をシャッフルし、各間隔で
「JST基準でちょうどN日前の0:00〜24:00に作成された例文」をクエリ。
候補の中からUVM P値が最低の1文を選出する（最大3文まで）。

### ② UVMフィラーで補充

①で埋まらなかった枠を、UVMの P値が低いキーワードに対応するユーザー例文から補充（`selectFillerSentencesByUvm`）。
同一キーワードの重複出題は避ける。

### UVM P値の取得

SRS候補例文の `key_word` を一括して
`users/{uid}/uvm/{word}` から `db.getAll()` で取得。UVM未登録語はデフォルト P=1（選出優先度最低）。

## ③ 例文が0件の場合

ユーザー例文が0件の場合、`{ questions: [], no_user_sentences: true }` を返す。
クライアント側で `QuizNoSentences` 状態に遷移し、例文生成を促すUIを表示する。

## ④ クイズ生成 — `generateQuestionsFromSources`

最大5問分の生成元を先に確定し、各例文ごとに `GeminiQuizService.generateQuizQuestions()` を並列呼び出しする。
LLMには `dummies`（ダミー選択肢3つ）・`explanation`・`dummy_reasons` のみを生成させ、
`blank_text`・`correct_answer` 等はルールベースで事前構築する（`applyRuleBasedQuizFields`）。

**key_word バリデーション**:
`key_word` が指定されている場合、`correct_answer` が `key_word` と一致するか確認。
不一致の問題は1回リトライし、それでも失敗したものはスキップする。

**コスト検証ログ**:
Gemini の `usageMetadata` から `Gemini token usage` ログに `requestMode`、`sentenceCount`、`promptTokens`、`candidatesTokens`、`thoughtsTokens`、`costUsd` を出力する。

### Gemini プロンプト — `quizGenerationService.ts`

LLMには `dummies`・`explanation`・`dummy_reasons` の3項目のみを生成させる。
`blank_text` と `correct_answer` はルールベースで事前構築済みのため、LLMは変更しない。

主なプロンプト制約:
- ダミーは品詞不一致・項構造不一致など局所的に破綻する語を選ぶ
- 代入して文法上/意味上入りうる語、同カテゴリ置換は不可
- 機能語同士（類別詞・指示詞・前置詞など）をダミーにしない
- `dummy_reasons` は各ダミーごとに異なる理由を記載

- max_output_tokens: 4096
- Gemini の `responseMimeType: 'application/json'` + `responseSchema` で JSON 形式を強制

### サニタイズ — `sanitizeQuizQuestion`

1. `correct_answer` がタイ語文字（`\u0E00-\u0E7F`）でなければ問題をドロップ
2. `choices` からタイ語以外（日本語・英語・ラテン文字）を除外し、重複を排除
3. 4択に満たなければ問題をドロップ
4. `dummy_reasons` が3つの不正解選択肢それぞれに対応しているか確認（未対応ならドロップ）
5. 選択肢をシャッフルし、各選択肢の発音を `dummy_reasons` から抽出して `choice_pronunciations` を構築

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
| `srs_interval` | 選出時のSRS間隔（-1: UVMフィラー、0: 学習クイズ、1/3/7/14/30: SRS日数）|
| `japanese_translation` | 例文の日本語訳 |
| `sentence_pronunciation` | 例文全体の発音 |
