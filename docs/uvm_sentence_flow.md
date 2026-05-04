# UVM → 例文生成フロー

## 全体像

```
[UVM作成(premium)] → [単語選定] → [プロンプト構築] → [Gemini API] → [NLP後処理] → [exposure更新]
```

premiumユーザーのUVMは初期状態0単語で作成され、クイズ結果により単語が蓄積される。

## 1. 例文生成リクエスト

**トリガー**: ユーザーが例文生成ボタンを押す → `generateThaiSentence`

### 1a. UVM連動の判定

```
premium → premium spec
free → free spec（語彙帯域を FREE_TIER_MAX_VOCAB で上限）
```

### 1b. ターゲット単語の選定（`select_uvm_target_words` → `get_session_words`）

```
get_freq_rank()           # GCSからtop10000の頻度辞書を取得
    ↓
estimated_vocab ± band    # 帯域内の候補単語を抽出
  band = [estimated_vocab - 100, estimated_vocab + 10]
    ↓
UVMのP値を参照し priority 順にソート
  priority = (effective_p ASC, rank距離 ASC, random)
    ↓
先頭から count 語を選出（generateThaiSentence はデフォルト count=1）
    ↓
key_word のembeddingからテーマを自動選択（topic未指定時）
```

#### 帯域フィルタの詳細

| 定数 | 値 | 意味 |
|------|----|------|
| `FREQ_BAND_LOOKBACK` | 100 | 帯域の後方幅（既知語寄り） |
| `FREQ_BAND_FORWARD` | 10 | 帯域の前方幅（未知語寄り） |
| `FREE_TIER_MAX_VOCAB` | 300 | free ティアの語彙上限 |

priorityキーはタプルの昇順ソートで決まる：

| 要素 | 優先される条件 | 意味 |
|------|--------------|------|
| `effective_p` | 小さいほど優先 | P値が低い＝まだ覚えていない単語を優先 |
| `distance` | 小さいほど優先 | `estimated_vocab` に rank が近い単語を優先（P値が同じ場合のみ効く） |
| `random.random()` | ランダム | タイブレーク |

UVM未登録語は `NEW_WORD_P=0.1` を effective_p として使用する。
P値が同値の場合は `estimated_vocab` に rank が近い単語（習熟境界付近）が優先されるため、「今まさに習得しかけている単語」が選ばれやすくなる。

### 1c. プロンプト構築（`build_uvm_prompt`）

通常のpremiumパラメータ（テーマ・文体等）に加え、ターゲット単語を指示に含める：

```
【重要】以下のタイ語単語をできるだけ多く自然に含む例文にしてください:
กิน, น้ำ, อร่อย
（全ての単語を無理に含める必要はありません。自然な文になることを優先してください。）
```

### 1d. Gemini API呼び出し → NLP後処理

1. premium spec なら `GEMINI_MODEL_PREMIUM`、free spec なら `GEMINI_MODEL` を使用
2. target_wordsが例文に含まれているかを検証し、不足があれば最大1回リトライ
3. `enrich_with_nlp()` で音節分割・発音変換・品詞タグ付けを付与

### 1e. exposure更新（`_register_sentence_exposure`）

生成された例文の `word_breakdown` を走査し、2種類の露出を登録する：

1. **ターゲット語**: target_words と一致した単語 → `register_exposure` で P 微増・`last_seen` 更新
2. **その他の単語**: 例文中の残りの単語も同様に露出登録

露出による P 更新式: `p = p + ALPHA_EXPOSURE * (1 - p)`（`ALPHA_EXPOSURE=0.03`）

exposure 登録後、`sync_estimated_vocab` で `estimated_vocab` を再計算・更新する。

## 2. クイズによるUVM更新

クイズ回答後 → `updateUvm` Cloud Function → `batch_update_uvm()`

P 更新式は **rank依存のalpha** を使用する（高頻度語ほど大きく変化）：

```
scale = RANK_SCALE_REF / (rank + RANK_SCALE_REF)   # rank低いほど1に近い
alpha_max = MAX_LOW + (MAX_TOP - MAX_LOW) * scale
alpha = MIN + (alpha_max - MIN) * exp(-ALPHA_DECAY_K * quiz_attempts)

正解: p = p + alpha * (1 - p)
不正解: p = p - alpha * p
```

| rank帯 | 正解時の挙動（quiz_attempts=0, p=0.1から） |
|--------|------------------------------------------|
| rank ≈ 1（高頻度語） | 1問正解で P > 0.5 |
| rank ≈ 600 | 2問正解で P > 0.5 |
| rank > 3000（低頻度語） | 3問正解で P > 0.5 |

更新後に `sync_estimated_vocab` で `estimated_vocab` を再計算する。

## Firestoreドキュメント構造

### `users/{uid}/uvm/{word}`

| フィールド | 型 | 説明 |
|-----------|-----|------|
| `p` | float | P(know) 確率 (0.0〜0.99) |
| `quiz_attempts` | int | クイズ回答回数（alpha減衰に使用） |
| `last_seen` | float | 最終閲覧 Unix timestamp |
| `last_result` | bool | 直近の正誤 |

### `users/{uid}`

| フィールド | 型 | 説明 |
|-----------|-----|------|
| `estimated_vocab` | int | 語彙境界（P≈0.5 となる freq_rank） |

## データソース

| データ | 格納先 | 生成方法 |
|--------|--------|----------|
| freq_rank_top10000.json | GCS `{project}-uvm-data` | `scripts/build_freq_rank.py` |
| vocab_embeddings.npy | GCS `{project}-uvm-data` | `scripts/build_embeddings.py` |
| vocab_words.json | GCS `{project}-uvm-data` | `scripts/build_embeddings.py` |
| UVMドキュメント | Firestore `users/{uid}/uvm/{word}` | register_exposure / batch_update_uvm |
