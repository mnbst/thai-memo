# NLP 差分テストハーネス

Python の Thai NLP スタック（PyThaiNLP / TLTK）を Go へ移植する際に、
**出力が1文字も変わらないこと**を機械的に保証するための golden テスト基盤。

移植の前に golden を固定し、Go 実装がそれに 100% 一致するまでリリースしない。

## 3ステップ

```bash
cd functions/python

# 1. コーパス抽出（既定は辞書。Firestore 不要）
.venv/bin/python scripts/nlp_golden/extract_corpus.py --source dict \
  --out scripts/nlp_golden/data/corpus.jsonl

# 2. golden 生成（Python が正解）。8コアで約37分
.venv/bin/python scripts/nlp_golden/gen_golden.py \
  --corpus scripts/nlp_golden/data/corpus.jsonl \
  --out scripts/nlp_golden/data/golden.jsonl --check-determinism

# 3. 候補実装の検証（Go が同じ JSONL を吐く）
go run ./cmd/nlpdump --corpus .../corpus.jsonl > candidate.jsonl
.venv/bin/python scripts/nlp_golden/verify.py \
  --golden scripts/nlp_golden/data/golden.jsonl \
  --candidate candidate.jsonl
```

## コーパスは辞書から取る

`--source dict` が既定。PyThaiNLP / TLTK にバンドルされた辞書 **78,765語**を使う。

| ソース | 件数 |
|---|---|
| `tltk/BEST.dict` | 33,200 — th2ipa が実際に引く辞書そのもの |
| `pythainlp/corpus/words_th.txt` | 62,098 |
| `pythainlp/corpus/syllables_th.txt` | 10,322 |

辞書は入力空間そのものなので、本番データ（＝よく使う語に偏った部分集合）より
網羅性が高い。Firestore 不要・決定的・CI で回せる。

`--source firestore` は補助。辞書に無い借用語・固有名詞など、実際に生成された
データを追加で拾いたいときに使う。

## 2層の契約

**tier1（契約層）** — 呼び出し側が依存する公開API。ここが1件でも不一致なら FAIL。

| api | 出力元 |
|---|---|
| `thai_to_pronunciation` | pronunciation.py:211 — ユーザーに見える発音表記 |
| `segment_syllables` | nlp.py:209 |
| `get_pos_japanese` | nlp.py:226 |
| `tokenize_words` | word_gap.py:142 |

**tier2（診断層）** — tier1 が壊れたときに原因を切り分けるためのプリミティブ。
単体では FAIL 判定に使わない。

| api | 出力元 |
|---|---|
| `th2ipa` | TLTK |
| `subword_tokenize` | PyThaiNLP (engine=dict) |
| `pos_tag_unigram_tud` | PyThaiNLP |
| `pos_tag_perceptron_orchid_ud` | PyThaiNLP |

## Go 側が実装すべきこと

`corpus.jsonl` を読み、同じ `{api, in, out}` の JSONL を stdout に吐く CLI。
キーの順序・浮動小数点は出力に含まれないため、比較は文字列一致で足りる。

## 重要: th2ipa は純関数ではない

**TLTK の `th2ipa` は推論中に自分の n-gram 統計モデルを書き換える。**

```python
# tltk/th2ipa.py:893-897
if BiCount[(w1,w2)] < 1 or Count[w1] < 1 or Count[w2] < 1:
    BiCount[(w1,w2)] += 1      # 未知バイグラムを「学習」してしまう
    Count[w1] += 1
    Count[w2] += 1
    TotalWord += 2
```

加算スムージングをグローバル変数の破壊的更新で実装しているため、
**同じ入力でもプロセスが直前に何を処理したかで出力が変わる**。

実例（2,000語コーパス）:

```
th2ipa("ทร.")  単独          -> 'tʰᴐːtʰᴐː1'
th2ipa("ทร.")  ป.กศ. の後    -> 'tʰᴐː1.ra4.cut2'
```

### 本番への影響

Cloud Functions のインスタンスは使い回される。したがって現在の本番でも、
**同じタイ語が、そのインスタンスの処理履歴によって違う発音表記になりうる**。
発生率は低い（2,000語中 tier1 で1件、0.02%）が、略語・希少借用語に集中する。

### ハーネスでの扱い

既定（`PURE = True`）で、各呼び出しの前に `BiCount` / `Count` / `TotalWord` を
初期状態へ戻す。オーバーヘッドは実測 6%。

- 2,000語での検証: `--check-determinism` の unstable が **1件 → 0件**
- **pure と impure で出力の差分は 0件**。つまり状態リセットは出力を変えず、
  非決定性だけを除去する

`--impure` を付けると現行本番と同じ履歴依存の挙動を再現できる。

## そのほかの既知のリスク

`ProbPhone` は tri/bi/unigram を対数補間した argmax で音素を選ぶ。
Python の `math.log` と Go の `math.Log` は最終 ULP が一致しない場合があり、
僅差の候補で選択が反転しうる。不一致が出たら **加算順序とタイブレークを
Python 側に揃える**こと。tier2 の `th2ipa` 不一致がこの兆候になる。

辞書の見出し語にはハイフン記法（`เอ่ย-ย`）が含まれ、`th2ipa` はこれで
例外を投げる。golden には `{"__error__": true}` と記録される。Go 側も
同じ入力で失敗すれば一致とみなす（例外メッセージの一致は要求しない）。
