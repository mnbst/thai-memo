"""UVM (User Vocabulary Model) コアロジック

ユーザーごとの語彙習得状態を管理する。
Firestore の users/{uid}/uvm/{word} コレクションに対して読み書きを行う。

【Firestore ドキュメント構造】
  users/{uid}/uvm/{word}:
    - p: float           — P(know) 確率 (0.01〜0.99)
    - exposures: int     — この単語を見た総回数
    - correct: int       — 正解した回数
    - last_seen: float   — 最終閲覧 Unix timestamp
    - last_result: bool  — 直近の正誤

【主な機能】
  - トピック×語彙レベルに基づくセッション単語の選定 (get_session_words)
  - P(know) 確率の更新 (update_p)
  - クイズ結果からの一括更新 (batch_update_uvm)
  - 推定語彙数の算出 (estimate_vocab, sync_vocab_count)
"""

import random
import time
from typing import Any

from google.cloud.firestore_v1.client import Client as FirestoreClient
from embeddings import get_topic_similar_words

# ---------------------------------------------------------------------------
# 定数
# ---------------------------------------------------------------------------
ALPHA = 0.2  # P(know) 更新時の学習率
P_MIN = 0.01  # P の下限
P_MAX = 0.99  # P の上限
NEW_WORD_P = 0.2  # 新規単語の初期 P 値

# get_session_words 用: estimated_vocab 基準の頻度帯フィルタ幅
FREQ_BAND_DEFAULT = 200  # 初期帯域: estimated_vocab 〜 +200
FREQ_BAND_FALLBACK = 500  # 候補不足時の拡大帯域


def estimate_vocab(
    docs: list,
    freq_rank: dict[str, int],
    p_threshold: float = 0.7,
) -> int:
    """UVM ドキュメント群から推定習得語数を算出する。

    p >= p_threshold の単語の freq_rank を集め、90 パーセンタイルを返す。
    「頻度順位 N の単語を知っていれば、それより頻出な単語もほぼ知っている」
    という仮定に基づく。
    """
    known_ranks: list[int] = []
    for doc in docs:
        p = (doc.to_dict() or {}).get("p", NEW_WORD_P)
        if p >= p_threshold:
            rank = freq_rank.get(doc.id)
            if rank is not None:
                known_ranks.append(rank)

    if not known_ranks:
        return 0

    # 頻度順位を昇順ソート（例: [12, 45, 120, 500, 1300]）
    known_ranks.sort()
    # 90パーセンタイルの位置を算出（配列末尾を超えないよう clamp）
    # → 「既知単語のうち上位90%がカバーする頻度順位」＝推定語彙数
    idx = min(int(len(known_ranks) * 0.9), len(known_ranks) - 1)
    return known_ranks[idx]


def sync_vocab_count(db: FirestoreClient, uid: str, freq_rank: dict[str, int]) -> None:
    """users/{uid} の vocab_count と estimated_vocab を同期する。"""
    uvm_ref = db.collection("users").document(uid).collection("uvm")
    docs = list(uvm_ref.select(["p"]).get())
    vocab_count = len(docs)
    estimated = estimate_vocab(docs, freq_rank)
    db.collection("users").document(uid).set(
        {"vocab_count": vocab_count, "estimated_vocab": estimated},
        merge=True,
    )


def update_p(p: float, correct: bool) -> float:
    """P(know) を正誤に基づいて更新する。

    【更新式】
      正解時: p_new = p + α(1 - p)  — 1.0 に近づくほど変化量が小さくなる
      不正解: p_new = p - α * p     — 0.0 に近づくほど変化量が小さくなる

    結果は [P_MIN, P_MAX] にクリッピングして返す。
    """
    if correct:
        p = p + ALPHA * (1 - p)
    else:
        p = p - ALPHA * p
    return max(P_MIN, min(P_MAX, p))


def get_session_words(
    db: FirestoreClient,
    uid: str,
    freq_rank: dict[str, int],
    topic: str,
    count: int = 1,
    api_key: str | None = None,
) -> list[str]:
    """トピック×語彙レベルに基づいてセッション単語を選定する。

    【選定ロジック】
    1. トピックのembeddingで語彙10000語との類似度を計算 → 上位500語
    2. ユーザーの estimated_vocab を Firestore から取得
    3. 500語のうち freq_rank が estimated_vocab 付近（少し難しい帯域）の単語をフィルタ
    4. フィルタ結果からランダムに count 語選出

    Args:
        db: Firestore クライアント
        uid: ユーザー UID
        freq_rank: {word: rank} — 頻出順位辞書
        topic: トピック文字列
        count: 選定する単語数（デフォルト 1）
        api_key: カスタムトピック時の Gemini API キー

    Returns:
        選定された単語のリスト
    """
    # 1. トピック関連上位500語を取得
    similar_words = get_topic_similar_words(topic, top_k=500, api_key=api_key)

    # 2. ユーザーの推定語彙数を取得
    user_doc = db.collection("users").document(uid).get()
    user_data = (user_doc.to_dict() or {}) if user_doc.exists else {}  # type: ignore
    estimated_vocab = user_data.get("estimated_vocab", 0)

    # 3. estimated_vocab より少し難しい帯域でフィルタ
    band_low = estimated_vocab
    band_high = estimated_vocab + FREQ_BAND_DEFAULT
    candidates = [w for w in similar_words if band_low <= w["rank"] <= band_high]

    # 候補不足時は帯域を広げる
    if len(candidates) < count:
        band_high = estimated_vocab + FREQ_BAND_FALLBACK
        candidates = [w for w in similar_words if band_low <= w["rank"] <= band_high]

    # それでも足りなければ類似度上位からそのまま使う
    if len(candidates) < count:
        candidates = similar_words

    # 4. ランダムに count 語選出
    selected = random.sample(candidates, min(count, len(candidates)))
    return [w["word"] for w in selected]


def batch_update_uvm(
    db: FirestoreClient,
    uid: str,
    results: list[dict[str, Any]],
    freq_rank: dict[str, int] | None = None,
) -> None:
    """クイズ/例文の正誤結果をもとに UVM を一括更新する。

    既存の UVM ドキュメントがあれば P を更新、なければ新規作成する。

    Args:
        db: Firestore クライアント
        uid: ユーザー UID
        results: [{"word": str, "is_correct": bool}, ...] — 各単語の正誤
    """
    now = time.time()
    batch = db.batch()
    uvm_ref = db.collection("users").document(uid).collection("uvm")
    new_words_count = 0

    for r in results:
        word = r["word"]
        is_correct = r["is_correct"]
        doc_ref = uvm_ref.document(word)
        doc = doc_ref.get()

        if doc.exists:
            # --- 既存単語の更新 ---
            data = doc.to_dict() or {}
            old_p = data.get("p", NEW_WORD_P)
            new_p = update_p(old_p, is_correct)
            batch.update(
                doc_ref,
                {
                    "p": new_p,
                    "exposures": data.get("exposures", 0) + 1,
                    "correct": data.get("correct", 0) + (1 if is_correct else 0),
                    "last_seen": now,
                    "last_result": is_correct,
                },
            )
        else:
            # --- 新規単語の作成（初めて見た単語） ---
            new_p = update_p(NEW_WORD_P, is_correct)
            batch.set(
                doc_ref,
                {
                    "word": word,
                    "p": new_p,
                    "exposures": 1,
                    "correct": 1 if is_correct else 0,
                    "last_seen": now,
                    "last_result": is_correct,
                },
            )
            new_words_count += 1

    batch.commit()

    if new_words_count > 0 and freq_rank is not None:
        sync_vocab_count(db, uid, freq_rank)
