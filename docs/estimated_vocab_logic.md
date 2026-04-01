# 推定語彙数（estimated_vocab）算出ロジック

## 概要

`estimated_vocab` は「P(know) ≈ 0.5 となる freq_rank」として定義される語彙境界値。
単語の習熟確率 P が 0.5 を下回り始める rank = 「まだ覚えていない単語の入り口」を表す。

## 算出フロー

```
UVMドキュメント群（対象範囲のみ取得）
    ↓
{rank: p} マップを構築
    ↓
moving_avg(rank) を center ± 50 の範囲でスキャン
    ↓
moving_avg < 0.5 となる最初の rank = estimated_vocab
```

## 関数詳細

### `moving_avg(words_by_rank, center, window=10)` — `uvm.py:56`

rank `center` 周辺 ±10 の範囲で P の単純平均を返す。

- 対象範囲: `[center - 10, center + 10]`（21語）
- UVM未登録語には `UNKNOWN_WORD_P = 0.3` を使用（スパース対策）

### `estimate_vocab(docs, freq_rank, center=0)` — `uvm.py:68`

語彙境界 rank を推定する。

#### ステップ

1. `docs` から `{rank: p}` マップを構築
2. **center 決定**: 引数が 0 の場合は P加重平均 rank を使用
   ```
   center = Σ(p × rank) / Σp
   ```
3. **スキャン**: `center - 50` ～ `center + 50` を順に走査し、`moving_avg(r) < 0.5` となる最初の `r` を返す
4. **フォールバック**: スパースデータ（スキャンで境界が見つからない場合）は `P > 0.5` の語の最大 rank を返す

#### 返値

```
max(known_max_rank, 最初にmoving_avg<0.5となるrank, 0)
```

`known_max_rank`（P>0.5の最大rank）を下回らないよう保証することで、過去に習得した単語の成果が消えない。

### `sync_estimated_vocab(db, uid, freq_rank)` — `uvm.py:116`

Firestoreの `users/{uid}.estimated_vocab` を効率的に更新する。

- 全UVMドキュメントを取得せず、`current_estimate ± 50` の範囲の単語のみ取得
- `estimate_vocab()` で再計算後、`merge=True` で書き込み

#### 呼び出しタイミング

| イベント | 呼び出し元 |
|---------|-----------|
| 例文生成後（exposure更新後） | `sentence_handlers.py` |
| クイズ結果更新後 | `uvm.py:batch_update_uvm()` |

## 定数

| 定数 | 値 | 用途 |
|------|----|------|
| `UNKNOWN_WORD_P` | 0.3 | UVM未登録語のprior P（moving_avg内で使用） |
| `NEW_WORD_P` | 0.1 | UVM新規登録時の初期 P |

## 例

```
estimated_vocab = 600 のユーザーが rank=580〜620 の単語を習得した場合:
  → moving_avg がその帯域で 0.5 を超える
  → スキャンが rank=620 付近まで進んで初めて < 0.5
  → estimated_vocab ≈ 620 に更新
```
