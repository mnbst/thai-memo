"""Embedding モジュール — 語彙のセマンティック類似度フィルタリング

GCSからembeddingデータをlazy-loadし、コサイン類似度で
セマンティック重複除去やトピック関連単語の検索を行う。

【データ形式】
  - vocab_embeddings.npy: (10000, 768) float32 — Gemini Embedding モデルの出力
  - vocab_words.json: [{"word": "ฉัน", "rank": 1}, ...] — npy の行番号と対応
  - topic_embeddings.json: {"トピック文字列": [float, ...], ...} — 事前計算済み
"""

import io
import json
import os
from typing import Any

import numpy as np
from google.cloud import storage

# ---------------------------------------------------------------------------
# グローバルキャッシュ
# Cloud Functions はコンテナが再利用されるため、初回ロード後はメモリ上に保持し
# 2回目以降の GCS アクセスを回避する。
# ---------------------------------------------------------------------------
_embeddings: np.ndarray | None = None  # (10000, 768) の embedding 行列
_word_to_idx: dict[str, int] | None = None  # 単語 → _embeddings の行インデックス
_words: list[dict[str, Any]] | None = None  # vocab_words.json の中身
_topic_embeddings: dict[str, list[float]] | None = None  # トピック→embedding

GCS_BUCKET = os.environ.get("UVM_DATA_BUCKET", "")
EMB_BLOB = "vocab_embeddings.npy"
WORDS_BLOB = "vocab_words.json"
TOPIC_EMB_BLOB = "topic_embeddings.json"


def _load_data() -> None:
    """GCS から embedding データをダウンロードしグローバル変数にキャッシュする。

    既にロード済み (_embeddings is not None) の場合は何もしない。
    Cloud Functions のコールドスタート時に 1 回だけ実行される。
    """
    global _embeddings, _word_to_idx, _words

    if _embeddings is not None:
        return  # キャッシュ済み — スキップ

    bucket = _get_bucket()

    # --- embedding 行列のロード ---
    # npy バイナリを GCS からメモリに読み込み、numpy 配列に変換
    emb_blob = bucket.blob(EMB_BLOB)
    emb_bytes = emb_blob.download_as_bytes()
    _embeddings = np.load(
        io.BytesIO(emb_bytes),
        allow_pickle=False,
    )

    # --- 単語メタデータのロード ---
    # vocab_words.json の各要素 {"word": "xxx", "rank": N} を読み込み、
    # word → 行インデックスの逆引き辞書を構築
    words_blob = bucket.blob(WORDS_BLOB)
    words_json = words_blob.download_as_text()
    _words = json.loads(words_json)

    _word_to_idx = {}
    for i, entry in enumerate(_words):  # pyright: ignore[reportArgumentType]
        _word_to_idx[entry["word"]] = i  # i が _embeddings[i] に対応


def _get_bucket():
    """GCS バケットオブジェクトを返す。"""
    bucket_name = GCS_BUCKET
    if not bucket_name:
        project_id = os.environ.get("GCLOUD_PROJECT", "")
        bucket_name = f"{project_id}-uvm-data"
    client = storage.Client()
    return client.bucket(bucket_name)


def _load_topic_embeddings() -> None:
    """GCS から topic_embeddings.json をロードしキャッシュする。"""
    global _topic_embeddings
    if _topic_embeddings is not None:
        return

    bucket = _get_bucket()
    blob = bucket.blob(TOPIC_EMB_BLOB)
    _topic_embeddings = json.loads(blob.download_as_text())


def get_topic_similar_words(
    topic: str,
    top_k: int = 500,
    api_key: str | None = None,
) -> list[dict[str, Any]]:
    """トピックに関連する上位 top_k 語を返す。

    事前計算済みトピックembeddingと一致する場合はそれを使い、
    カスタム入力の場合は Gemini Embedding API でリアルタイム変換する。

    Returns:
        [{"word": str, "rank": int, "similarity": float}, ...]
        similarity 降順でソート済み。
    """
    _load_data()
    _load_topic_embeddings()
    assert _embeddings is not None and _words is not None
    assert _topic_embeddings is not None

    # 事前計算済みトピックから検索（完全一致 or 部分一致）
    topic_emb: np.ndarray | None = None
    for key, emb_list in _topic_embeddings.items():
        if topic == key or topic in key or key in topic:
            topic_emb = np.array(emb_list, dtype=np.float32)
            break

    # 一致しない場合は Gemini Embedding API でリアルタイム変換
    if topic_emb is None:
        if not api_key:
            raise ValueError(f"Unknown topic and no API key for embedding: {topic}")
        from google import genai

        client = genai.Client(api_key=api_key)
        result = client.models.embed_content(
            model="gemini-embedding-001",
            contents=topic,
        )
        topic_emb = np.array(result.embeddings[0].values, dtype=np.float32)  # type: ignore

    # 全語彙とのコサイン類似度を一括計算（行列演算）
    norms = np.linalg.norm(_embeddings, axis=1)
    topic_norm = np.linalg.norm(topic_emb)
    similarities = np.dot(_embeddings, topic_emb) / (norms * topic_norm + 1e-10)

    # 上位 top_k のインデックスを取得
    top_indices = np.argsort(similarities)[::-1][:top_k]

    results: list[dict[str, Any]] = []
    for idx in top_indices:
        entry = _words[idx]
        results.append(
            {
                "word": entry["word"],
                "rank": entry["rank"],
                "similarity": float(similarities[idx]),
            }
        )

    return results


def get_embedding(word: str) -> np.ndarray | None:
    """指定した単語の embedding ベクトル (768次元) を返す。

    語彙リスト (top10000) に含まれない未知語の場合は None を返す。
    """
    _load_data()
    assert _embeddings is not None and _word_to_idx is not None
    idx = _word_to_idx.get(word)
    if idx is None:
        return None
    return _embeddings[idx]


def cosine_similarity(a: np.ndarray, b: np.ndarray) -> float:
    """2つのベクトルのコサイン類似度を計算する。

    戻り値は -1.0〜1.0。1.0 に近いほど意味が似ている。
    ゼロベクトルが渡された場合は 0.0 を返す。
    """
    dot = np.dot(a, b)
    norm = np.linalg.norm(a) * np.linalg.norm(b)
    if norm == 0:
        return 0.0
    return float(dot / norm)


def filter_semantic_duplicates(
    candidates: list[dict[str, Any]],
    selected: list[dict[str, Any]],
    threshold: float = 0.85,
) -> list[dict[str, Any]]:
    """選定済み単語と意味的に重複する候補を除去する。

    【使い方】
    get_session_words() で復習単語を先に確定した後、新規単語候補に対して
    この関数を適用し、復習単語と意味が被る候補を除外する。

    Args:
        candidates: フィルタ対象の単語リスト（各要素に "word" キー必須）
        selected: 既に選定済みの単語リスト（復習単語など）
        threshold: この値以上のコサイン類似度を持つ候補を除外（デフォルト 0.85）

    Returns:
        重複除去後の候補リスト
    """
    _load_data()

    # 選定済み単語の embedding を事前に取得しておく
    selected_embs: list[np.ndarray] = []
    for s in selected:
        emb = get_embedding(s["word"])
        if emb is not None:
            selected_embs.append(emb)

    # 選定済みに embedding がない場合はフィルタ不要
    if not selected_embs:
        return candidates

    filtered: list[dict[str, Any]] = []
    for c in candidates:
        emb = get_embedding(c["word"])
        if emb is None:
            # embedding が取れない単語はフィルタ対象外としてそのまま残す
            filtered.append(c)
            continue

        # 選定済みのどれかと類似度が閾値以上なら重複とみなす
        is_dup = False
        for sel_emb in selected_embs:
            if cosine_similarity(emb, sel_emb) >= threshold:
                is_dup = True
                break

        if not is_dup:
            filtered.append(c)

    return filtered


def get_diverse_new_words(
    candidates: list[dict[str, Any]],
    count: int,
    threshold: float = 0.85,
) -> list[dict[str, Any]]:
    """候補から意味的に多様な新規単語を選定する。

    【アルゴリズム — 貪欲法（greedy selection）】
    候補を先頭から順に見ていき、既に選定した単語のどれとも
    コサイン類似度が閾値未満であれば採用する。
    これにより、同義語・類義語が同時に選ばれることを防ぐ。

    例: candidates に "กิน"(食べる) と "ทาน"(食べる/召し上がる) が含まれる場合、
        先に "กิน" が選ばれると "ทาน" は類似度が高いため除外される。

    Args:
        candidates: 候補単語リスト（freq_rank 順を推奨 — 頻出語が優先される）
        count: 選定する単語数
        threshold: 重複判定の閾値

    Returns:
        選定された単語リスト（最大 count 件）
    """
    _load_data()

    result: list[dict[str, Any]] = []
    result_embs: list[np.ndarray] = []  # 選定済み単語の embedding を保持

    for c in candidates:
        if len(result) >= count:
            break

        emb = get_embedding(c["word"])
        if emb is None:
            # embedding なしの単語は無条件で採用
            result.append(c)
            continue

        # 既に選定した単語との類似度チェック
        is_dup = False
        for r_emb in result_embs:
            if cosine_similarity(emb, r_emb) >= threshold:
                is_dup = True
                break

        if not is_dup:
            result.append(c)
            result_embs.append(emb)  # 次の候補との比較用に保持

    return result
