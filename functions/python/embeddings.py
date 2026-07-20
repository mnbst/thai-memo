"""Embedding モジュール — 語彙のセマンティック類似度フィルタリング

GCSからembeddingデータをlazy-loadし、コサイン類似度で
セマンティック重複除去やテーマ関連単語の検索を行う。

【データ形式】
  - vocab_embeddings.npy: (10000, 768) float32 — Gemini Embedding モデルの出力
  - vocab_words.json: [{"word": "ฉัน", "rank": 1}, ...] — npy の行番号と対応
  - topic_embeddings.json: {"テーマ文字列": [float, ...], ...} — 事前計算済み
  - emotion_embeddings.json: {"感情ラベル": [float, ...], ...} — 事前計算済み
  - style_embeddings.json: {"文体ラベル": [float, ...], ...} — 事前計算済み
  - politeness_embeddings.json: {"丁寧さラベル": [float, ...], ...} — 事前計算済み
"""

import io
import json
import os
import random
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
_topic_embeddings: dict[str, list[float]] | None = None  # テーマ→embedding
_emotion_embeddings: dict[str, list[float]] | None = None  # 感情→embedding
_style_embeddings: dict[str, list[float]] | None = None  # 文体→embedding
_politeness_embeddings: dict[str, list[float]] | None = None  # 丁寧さ→embedding

GCS_BUCKET = os.environ.get("UVM_DATA_BUCKET", "")
EMB_BLOB = "vocab_embeddings.npy"
WORDS_BLOB = "vocab_words.json"
TOPIC_EMB_BLOB = "topic_embeddings.json"
EMOTION_EMB_BLOB = "emotion_embeddings.json"
STYLE_EMB_BLOB = "style_embeddings.json"
POLITENESS_EMB_BLOB = "politeness_embeddings.json"


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


def _load_emotion_embeddings() -> None:
    """GCS から emotion_embeddings.json をロードしキャッシュする。"""
    global _emotion_embeddings
    if _emotion_embeddings is not None:
        return

    bucket = _get_bucket()
    blob = bucket.blob(EMOTION_EMB_BLOB)
    _emotion_embeddings = json.loads(blob.download_as_text())


def _load_style_embeddings() -> None:
    """GCS から style_embeddings.json をロードしキャッシュする。"""
    global _style_embeddings
    if _style_embeddings is not None:
        return

    bucket = _get_bucket()
    blob = bucket.blob(STYLE_EMB_BLOB)
    _style_embeddings = json.loads(blob.download_as_text())


def _load_politeness_embeddings() -> None:
    """GCS から politeness_embeddings.json をロードしキャッシュする。"""
    global _politeness_embeddings
    if _politeness_embeddings is not None:
        return

    bucket = _get_bucket()
    blob = bucket.blob(POLITENESS_EMB_BLOB)
    _politeness_embeddings = json.loads(blob.download_as_text())


def _find_embedding(
    label: str,
    embeddings: dict[str, list[float]],
) -> np.ndarray | None:
    for key, emb_list in embeddings.items():
        if label == key or label in key or key in label:
            return np.array(emb_list, dtype=np.float32)
    return None


def get_topic_embedding(topic: str) -> np.ndarray | None:
    """テーマ文字列のembeddingベクトルを返す。"""
    _load_topic_embeddings()
    assert _topic_embeddings is not None
    return _find_embedding(topic, _topic_embeddings)


def get_topic_similar_words(
    topic: str,
    top_k: int = 500,
    api_key: str | None = None,
) -> list[dict[str, Any]]:
    """テーマに関連する上位 top_k 語を返す。

    事前計算済みテーマembeddingと一致する場合はそれを使い、
    カスタム入力の場合は Gemini Embedding API でリアルタイム変換する。

    Returns:
        [{"word": str, "rank": int, "similarity": float}, ...]
        similarity 降順でソート済み。
    """
    _load_data()
    _load_topic_embeddings()
    assert _embeddings is not None and _words is not None
    assert _topic_embeddings is not None

    # 事前計算済みテーマから検索（完全一致 or 部分一致）
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


def find_best_topic(
    word: str,
    topics: list[str] | None = None,
    top_k: int = 5,
    threshold: float = 0.0,
) -> str | None:
    """key_word の embedding と各テーマ embedding のコサイン類似度からテーマを返す。

    閾値以上の候補を類似度順に並べ、上位 top_k 件からランダムに1件選択する。
    閾値を満たす候補がない場合は最高類似度のテーマを返す。

    Args:
        word: key_word（タイ語単語）
        topics: 候補テーマリスト。None なら事前計算済み全テーマから選択。
        top_k: ランダム選択するプール上限（デフォルト 5）
        threshold: コサイン類似度の下限（デフォルト 0.0）

    Returns:
        選択されたテーマ文字列。embedding が取得できない場合は None。
    """
    _load_data()
    _load_topic_embeddings()
    assert _topic_embeddings is not None

    word_emb = get_embedding(word)
    if word_emb is None:
        return None

    scored: list[tuple[float, str]] = []
    for topic_str, emb_list in _topic_embeddings.items():
        if topics is not None and not any(
            t in topic_str or topic_str in t for t in topics
        ):
            continue
        topic_emb = np.array(emb_list, dtype=np.float32)
        sim = cosine_similarity(word_emb, topic_emb)
        scored.append((sim, topic_str))

    if not scored:
        return None

    scored.sort(reverse=True)
    candidates = [t for sim, t in scored if sim >= threshold]
    pool = (candidates or [scored[0][1]])[:top_k]
    return random.choice(pool)


_sub_theme_embeddings: dict[str, list[float]] | None = None
SUB_THEME_EMB_BLOB = "sub_theme_embeddings.json"
_shot_embeddings: dict[str, list[float]] | None = None
SHOT_EMB_BLOB = "shot_embeddings.json"


def _load_sub_theme_embeddings() -> None:
    global _sub_theme_embeddings
    if _sub_theme_embeddings is not None:
        return
    bucket = _get_bucket()
    blob = bucket.blob(SUB_THEME_EMB_BLOB)
    _sub_theme_embeddings = json.loads(blob.download_as_text())


def _load_shot_embeddings() -> None:
    global _shot_embeddings
    if _shot_embeddings is not None:
        return
    bucket = _get_bucket()
    blob = bucket.blob(SHOT_EMB_BLOB)
    _shot_embeddings = json.loads(blob.download_as_text())


def _weighted_pick(scored: list[tuple[float, Any]]) -> Any:
    """類似度スコアを min-max 正規化し、重みつきランダムで1件選ぶ。

    下駄 0.1 により最下位でも選ばれる余地を残す（多様性の確保）。
    """
    min_sim = min(s for s, _ in scored)
    max_sim = max(s for s, _ in scored)
    if max_sim == min_sim:
        return random.choice(scored)[1]
    weights = [(sim - min_sim) / (max_sim - min_sim) + 0.1 for sim, _ in scored]
    return random.choices([item for _, item in scored], weights=weights, k=1)[0]


def find_best_drama_shot(word: str, shots: dict[str, str]) -> str | None:
    """単語embeddingと各セリフのembeddingの類似度で最適なショットを1つ選ぶ。

    Args:
        word: ターゲット単語（タイ語）
        shots: {ショットID: タイ語セリフ}

    Returns:
        選出されたショットID。embedding が引けない場合は None（呼び出し側で
        ランダムにフォールバックする）。
    """
    _load_data()
    _load_shot_embeddings()
    assert _shot_embeddings is not None

    word_emb = get_embedding(word)
    if word_emb is None:
        return None

    scored: list[tuple[float, str]] = []
    for shot_id, text in shots.items():
        emb_list = _shot_embeddings.get(text)
        # 次元不一致（生成時の output_dimensionality 違い等）は候補から外す。
        # 例文生成そのものを落とさず、ランダム選出へ縮退させる。
        if emb_list is None or len(emb_list) != word_emb.shape[0]:
            continue
        sim = cosine_similarity(word_emb, np.array(emb_list, dtype=np.float32))
        scored.append((sim, shot_id))

    if not scored:
        return None
    return _weighted_pick(scored)


def find_best_sub_theme(
    word: str,
    sub_themes: list[str],
) -> str:
    """単語embeddingとサブテーマ群のコサイン類似度で重みつきランダム選出する。"""
    _load_data()
    _load_sub_theme_embeddings()
    assert _sub_theme_embeddings is not None

    word_emb = get_embedding(word)
    if word_emb is None:
        return random.choice(sub_themes)

    scored: list[tuple[float, str]] = []
    for st in sub_themes:
        emb_list = _sub_theme_embeddings.get(st)
        if emb_list is None:
            continue
        st_emb = np.array(emb_list, dtype=np.float32)
        sim = cosine_similarity(word_emb, st_emb)
        scored.append((sim, st))

    if not scored:
        return random.choice(sub_themes)

    min_sim = min(s for s, _ in scored)
    max_sim = max(s for s, _ in scored)
    if max_sim == min_sim:
        return random.choice(sub_themes)

    weights = [(sim - min_sim) / (max_sim - min_sim) + 0.1 for sim, _ in scored]
    return random.choices([st for _, st in scored], weights=weights, k=1)[0]


def get_topic_option_similarity_weights(
    topic: str,
    options: list[str],
    kind: str,
    scale: float = 3.0,
) -> list[float] | None:
    """topic に近い style / politeness 候補を選びやすくする重みを返す。

    全候補を残しつつ、topic embedding と option embedding の類似度差で
    1.0〜(1.0 + scale) の範囲に正規化する。
    """
    if not topic or not options:
        return None

    _load_topic_embeddings()
    assert _topic_embeddings is not None

    if kind == "style":
        _load_style_embeddings()
        option_embeddings = _style_embeddings
    elif kind == "politeness":
        _load_politeness_embeddings()
        option_embeddings = _politeness_embeddings
    else:
        raise ValueError(f"Unsupported option embedding kind: {kind}")

    assert option_embeddings is not None

    topic_emb = _find_embedding(topic, _topic_embeddings)
    if topic_emb is None:
        return None

    scored: list[tuple[float, int]] = []
    for i, option in enumerate(options):
        option_emb = _find_embedding(option, option_embeddings)
        if option_emb is None:
            continue
        scored.append((cosine_similarity(topic_emb, option_emb), i))

    if not scored:
        return None

    min_similarity = min(sim for sim, _ in scored)
    max_similarity = max(sim for sim, _ in scored)
    if max_similarity == min_similarity:
        return [1.0] * len(options)

    weights = [1.0] * len(options)
    for similarity, i in scored:
        normalized = (similarity - min_similarity) / (max_similarity - min_similarity)
        weights[i] = 1.0 + normalized * scale
    return weights


def get_style_similarity_weights(
    target_words: list[str] | None,
    styles: list[str],
    top_k: int = 3,
) -> list[float] | None:
    """target_words に近い文体ラベルだけを選びやすくする重みを返す。

    語彙 embedding と事前計算済み style_embeddings.json を比較し、
    類似度上位 top_k の文体だけをランダム選択候補に残す。
    embedding が取得できない場合は None を返し、呼び出し側で通常ランダムに戻す。
    """
    if not target_words:
        return None

    _load_data()
    _load_style_embeddings()
    assert _style_embeddings is not None

    target_embs = [
        emb for word in target_words if (emb := get_embedding(word)) is not None
    ]
    if not target_embs:
        return None

    target_emb = np.mean(np.stack(target_embs), axis=0)
    scored: list[tuple[float, int]] = []
    for i, style in enumerate(styles):
        style_emb = _find_embedding(style, _style_embeddings)
        if style_emb is None:
            continue
        scored.append((cosine_similarity(target_emb, style_emb), i))

    if not scored:
        return None

    scored.sort(reverse=True)
    top = scored[: max(1, min(top_k, len(scored)))]
    min_similarity = min(sim for sim, _ in top)
    weights = [0.0] * len(styles)
    for similarity, i in top:
        weights[i] = 1.0 + max(0.0, similarity - min_similarity) * 20.0
    return weights


def get_emotion_similarity_weights(
    target_words: list[str] | None,
    emotions: list[str],
    top_k: int = 3,
) -> list[float] | None:
    """target_words に近い感情ラベルだけを選びやすくする重みを返す。

    語彙 embedding と事前計算済み emotion_embeddings.json を比較し、
    類似度上位 top_k の感情だけをランダム選択候補に残す。
    embedding が取得できない場合は None を返し、呼び出し側で通常ランダムに戻す。
    """
    if not target_words:
        return None

    _load_data()
    _load_emotion_embeddings()
    assert _emotion_embeddings is not None

    target_embs = [
        emb for word in target_words if (emb := get_embedding(word)) is not None
    ]
    if not target_embs:
        return None

    target_emb = np.mean(np.stack(target_embs), axis=0)
    scored: list[tuple[float, int]] = []
    for i, emotion in enumerate(emotions):
        emotion_emb = _find_embedding(emotion, _emotion_embeddings)
        if emotion_emb is None:
            continue
        scored.append((cosine_similarity(target_emb, emotion_emb), i))

    if not scored:
        return None

    scored.sort(reverse=True)
    top = scored[: max(1, min(top_k, len(scored)))]
    min_similarity = min(sim for sim, _ in top)
    weights = [0.0] * len(emotions)
    for similarity, i in top:
        weights[i] = 1.0 + max(0.0, similarity - min_similarity) * 20.0
    return weights


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
