# UVM → 例文生成フロー

## 全体像

```
[UVM作成(premium)] → [単語選定] → [重複除去] → [プロンプト構築] → [Gemini API] → [NLP後処理] → [exposure更新]
```

premiumユーザーのUVMは初期状態0単語で作成され、クイズ結果により単語が蓄積される。

## 1. 例文生成リクエスト

**トリガー**: ユーザーが例文生成ボタンを押す → `generateThaiSentence`

### 1a. UVM連動の判定

```
premium → UVM連動モード
それ以外 → 通常の free プロンプト
```

### 1b. ターゲット単語の選定（`_select_uvm_target_words`）

```
_get_freq_rank()          # GCSからtop10000の頻度辞書を取得
    ↓
get_session_words()       # 復習70% + 新規30% で候補取得
    ↓
filter_semantic_duplicates()  # 新規候補から復習単語と意味が近いものを除去
    ↓
get_diverse_new_words()   # 新規候補内でも類義語を排除（貪欲法）
    ↓
最大5語のターゲット単語リスト
```

#### get_session_words の詳細

| 区分 | 比率 | 選定ロジック |
|------|------|-------------|
| 復習 | 70% | `next_review <= now` の単語を `priority` 降順で選定。priority = uncertainty(p*(1-p)) + time_decay |
| 新規 | 30% | freq_rank順で UVM未登録の単語。多め(×3)に取得し後段フィルタ前提 |

#### embedding重複除去

- GCSから `vocab_embeddings.npy`(10000×768) をlazy-load
- コサイン類似度 ≥ 0.85 の単語ペアを重複とみなし除外
- 例: "กิน"(食べる) と "ทาน"(召し上がる) の同時選定を防止

### 1c. プロンプト構築（`build_uvm_prompt`）

通常のpremiumパラメータ（トピック・文体等）に加え、ターゲット単語を指示に含める：

```
【重要】以下のタイ語単語をできるだけ多く自然に含む例文にしてください:
กิน, น้ำ, อร่อย
（全ての単語を無理に含める必要はありません。自然な文になることを優先してください。）
```

### 1d. Gemini API呼び出し → NLP後処理

1. `GEMINI_MODEL_PREMIUM` で JSON形式の例文を生成
2. `enrich_with_nlp()` で音節分割・発音変換・品詞タグ付けを付与

### 1e. exposure更新

生成された例文の `word_breakdown` とターゲット単語を照合し、実際に含まれた単語の `exposures` と `last_seen` を更新（Pは変更しない）。

## 2. クイズによるUVM更新

クイズ回答後 → `updateUvm` Cloud Function → `batch_update_uvm()`

- 正解: `p = p + 0.25(1-p)` — 1.0に漸近
- 不正解: `p = p - 0.2p` — 0.0に漸近
- `next_review` を再計算（pが高いほど間隔が長い）

## データソース

| データ | 格納先 | 生成方法 |
|--------|--------|----------|
| freq_rank_top10000.json | GCS `{project}-uvm-data` | `scripts/build_freq_rank.py` |
| vocab_embeddings.npy | GCS `{project}-uvm-data` | `scripts/build_embeddings.py` |
| vocab_words.json | GCS `{project}-uvm-data` | `scripts/build_embeddings.py` |
| UVMドキュメント | Firestore `users/{uid}/uvm/{word}` | update_exposure / batch_update_uvm |
