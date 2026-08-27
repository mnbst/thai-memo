# 語彙スコア別パラメータ解禁仕様

## 概要

`estimated_vocab` は、例文生成時の難易度と自動選択パラメータの候補絞り込みに使う。
解禁ゲートは `functions/go/internal/sentence/prompts.go` の生成パラメータ解決処理で適用される。
UVM の key_word から embedding でテーマを自動選択する経路でも、同じ topic gate を使う。

対象になるのは未指定パラメータの自動選択のみ。
ユーザーまたはクライアントが `topic` / `style` / `grammarFocus` を明示指定した場合、その値は語彙スコアのゲート外でも維持される。

## 適用順

1. ティア別の候補プールを決める
   - premium: `TOPICS` / `STYLES` を全候補にする。`grammarFocus` も有効。
   - free: テーマのプールは premium と共通（語彙ゲートのみ）。選び方だけが違い、free は一様抽選。`grammarFocus` は使わない。
2. `estimated_vocab` で topic / grammarFocus の自動選択候補を絞る。
3. topic / style / politeness / grammarFocus / emotion を確定し、プロンプトに入れる。

`style`、`politeness`、`emotion` は語彙スコアでは制限しない。tier 内の全候補から自動選択する。

## 難易度と文長

| estimated_vocab | ラベル | 語彙ヒント | 文長 |
|---:|---|---|---|
| 0-99 | 入門 | 超基本的な挨拶・身近な語彙のみ | 〜7単語 |
| 100-299 | 初級 | 基本的な日常語彙のみ | 〜7-8単語 |
| 300-599 | 初中級 | 日常語彙中心、やや応用的な表現も可 | 〜8-10単語 |
| 600-1499 | 中級 | 日常〜応用的な語彙、自然な表現 | 〜10-16単語 |
| 1500以上 | 上級 | 制限なし。慣用句・ネイティブに近い自然な表現 | 自然な長さ |

100-1499 の文長は `_compute_length_hint()` で線形補間する。

```
round(7 + (estimated_vocab - 100) / 1400 * 9)
```

文長は `thai_text` の生成ヒントであり、`word_breakdown` の件数上限とは別に扱う。
`word_breakdown` はプロンプトと JSON Schema の説明で最大20件にしている。

## 解禁サマリー

| estimated_vocab | premium 自動選択で解禁される内容 | free 自動選択で使える内容 |
|---:|---|---|
| 0-99 | 入門テーマ6件、全文体、文法4件 | 入門テーマ6件（一様抽選）、free文体2件、文法なし |
| 100-299 | 日常系テーマ5件追加、全文法 | 同6件＋日常系6件（一様抽選）、free文体2件、文法なし |
| 300-599 | 学校テーマ | free は `estimated_vocab` が100でキャップされるため変化なし |
| 600-1499 | 文化系テーマ3件。難易度ラベルが中級になる | 同上 |
| 1500以上 | パラメータ追加なし。難易度ラベルが上級になり文長が自然な長さになる | 同上 |

## topic

premium の自動選択では、`TOPIC_MIN_VOCAB` で topic ごとに候補入りする語彙スコアを決める。
明示指定された topic はゲート外でも維持される。

このゲートは以下の両方に適用する。

- topic 未指定時のプロンプト用ランダム選択
- UVM key_word から embedding で topic を自動選択する時の候補プール

### 0-99 で候補になるテーマ

| テーマ | premium | free |
|---|---|---|
| あいさつ | yes | yes |
| 食べ物 | yes | yes |
| 旅行 | yes | yes |
| 家族 | yes | yes |
| 買い物 | yes | yes |
| 天気 | yes | yes |

### 100-299 で premium に追加されるテーマ

| テーマ |
|---|
| 仕事 |
| 交通 |
| 健康 |
| 趣味 |
| 恋愛・男女関係 |

### 300-599 で premium に追加されるテーマ

| テーマ |
|---|
| 学校 |

### 600以上で premium に追加されるテーマ

| テーマ |
|---|
| 宗教・信仰 |
| 伝統・祭り |
| 礼儀作法 |

2026-08-14: free 専用プール `FREE_TOPICS`（4件）を廃止した。クライアントはテーマを送らず
free/premium ともサーバーが自動選出するので、tier でプールを分けても選択肢の差にならない。
free は `TOPIC_MIN_VOCAB` でゲートしたプールから**一様抽選**する（premium は embedding で
key_word に最も近いテーマ）。旧仕様は 4件プール × embedding 選出で BLドラマが 82.7% を
占めていた。free は `estimated_vocab` が 100 でキャップされるため、実質は入門6テーマ＋
min_vocab=100 の6テーマ。

BLドラマだけは語彙ゲートの外で、free には常に `FREE_BL_TOPIC_RATE`（10%）で混ぜる
（`constants.py`）。ゲート任せだと入門帯に一切出ないが、刺さる層への引きとして残すため。
残り90%が上記プール（BL を除く）の一様抽選。バンク生成（`scripts/build_free_sentence_bank.py`）
も同じ率で BL 枠を確保する。

`TOPIC_MIN_VOCAB` の根拠は、`scripts/corpus/freq_rank_top10000.json` の入門〜初中級帯域を実際に確認した結果。
入門帯域の汎用語は embedding で「恋愛」「伝統・祭り」などへ寄りやすいため、UVM 経路でも入門テーマに制限する。
初級帯域では `ทำงาน`、`รถ`、`หมอ`、`ยา`、`รัก` など日常系の根拠語が出る一方、宗教・伝統・礼儀作法は専用語彙が薄いため中級からにする。

## style

style は語彙スコアでは制限しない。
premium は最初から全件を候補にする。
free は tier 制限として常に `FREE_STYLES` の2件だけを候補にする。

| 文体 | min estimated_vocab | premium | free |
|---|---:|---|---|
| 口語体 | 0 | yes | yes |
| 丁寧語 | 0 | yes | yes |
| SNS・テキストメッセージ | 0 | yes | no |
| ニュース記事体 | 0 | yes | no |
| 物語・文学体 | 0 | yes | no |

## grammarFocus

`grammarFocus` は premium のみ有効。
free では `grammarFocus` は常に `None` になる。

| 文法フォーカス | min estimated_vocab |
|---|---:|
| 平叙文 | 0 |
| 疑問文 | 0 |
| 否定文 | 0 |
| 可能表現 | 0 |
| 条件文 | 100 |
| 比較表現 | 100 |
| 命令・依頼 | 100 |
| 過去・完了 | 100 |
| 助詞・接続詞 | 100 |

この表は `GRAMMAR_FOCUSES` と `GRAMMAR_MIN_VOCAB` の現行実装値を基準にしている。
`GRAMMAR_FOCUSES` の順序を変える場合は、`GRAMMAR_MIN_VOCAB` のキーも同時に確認する。

## politeness

語彙スコアによる制限はない。
topic との embedding 類似度で重み付けし、以下の全候補から自動選択する。

| 丁寧さ |
|---|
| フォーマル |
| カジュアル |
| 中立 |

## emotion

語彙スコアによる制限はない。
`target_words` との embedding 類似度で重み付けし、以下の全候補から自動選択する。

| 感情・トーン |
|---|
| 喜び・嬉しさ |
| 悲しみ・落ち込み |
| 驚き |
| 不安・心配 |
| 期待・楽しみ |
| 中立・平静 |

## 実装参照

| 内容 | 実装 |
|---|---|
| 難易度ラベル | `functions/go/internal/sentence/prompts.go` |
| 文長補間 | `functions/go/internal/sentence/prompts.go` |
| topic gate | `functions/go/internal/sentence/prompts.go` |
| UVM topic gate | `functions/go/internal/sentence/select.go` / `functions/go/internal/sentence/resolve.go` |
| style gate | 語彙スコア制限なし。tier 別候補は `FREE_STYLES` / `STYLES` |
| grammar gate | `functions/go/internal/sentence/prompts.go` |
| 選択肢リスト | `functions/go/internal/sentence/constants_data.go` |
