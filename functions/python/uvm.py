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
from collections import Counter
from typing import Any

from google.cloud.firestore_v1.client import Client as FirestoreClient

from embeddings import get_topic_similar_words

# ---------------------------------------------------------------------------
# 定数
# ---------------------------------------------------------------------------
ALPHA_CORRECT = 0.001  # クイズ正解時の P(know) 上昇率
ALPHA_INCORRECT = 0.0005  # クイズ不正解時の P(know) 下降率
P_MIN = 0.0  # P の下限
P_MAX = 0.99  # P の上限
NEW_WORD_P = 0.0001  # 新規単語の初期 P 値
ALPHA_EXPOSURE = 0.0001  # 例文露出時の P 微増率

# get_session_words 用: estimated_vocab 基準の頻度帯フィルタ幅
FREQ_BAND_HALF = 50  # 初期帯域: estimated_vocab ± 50
FREQ_BAND_FALLBACK_HALF = 100  # 候補不足時: estimated_vocab ± 100


def estimate_vocab(docs: list, freq_rank: dict[str, int]) -> int:
    """UVM ドキュメント群から推定習得語数を算出する。

    全単語の freq_rank を P(know) で加重平均して返す。
    p が高い単語の rank ほど強く反映される。
    """
    weighted_ranks: list[tuple[float, int]] = []
    for doc in docs:
        p = (doc.to_dict() or {}).get("p", NEW_WORD_P)
        rank = freq_rank.get(doc.id)
        if rank is not None:
            weighted_ranks.append((p, rank))

    if not weighted_ranks:
        return 0

    total_p = sum(p for p, _ in weighted_ranks)
    if total_p <= 0:
        return 0
    return int(sum(p * rank for p, rank in weighted_ranks) / total_p)


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
      正解時: p_new = p + α_correct(1 - p)  — 1.0 に近づくほど変化量が小さくなる
      不正解: p_new = p - α_incorrect * p   — 0.0 に近づくほど変化量が小さくなる

    結果は [P_MIN, P_MAX] にクリッピングして返す。
    """
    if correct:
        p = p + ALPHA_CORRECT * (1 - p)
    else:
        p = p - ALPHA_INCORRECT * p
    return max(P_MIN, min(P_MAX, p))


def get_session_words(
    db: FirestoreClient,
    uid: str,
    freq_rank: dict[str, int],
    topic: str,
    count: int = 1,
    api_key: str | None = None,
    max_vocab: int | None = None,
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
        max_vocab: 語彙帯域の上限（free ティアでは 300）。None なら制限なし。

    Returns:
        選定された単語のリスト
    """
    # 1. トピック関連上位500語を取得
    similar_words = get_topic_similar_words(topic, top_k=500, api_key=api_key)

    # max_vocab 制限がある場合、候補をその範囲内に絞る
    if max_vocab is not None:
        similar_words = [w for w in similar_words if w["rank"] <= max_vocab]

    # 2. ユーザーの推定語彙数を取得
    user_doc = db.collection("users").document(uid).get()
    user_data = (user_doc.to_dict() or {}) if user_doc.exists else {}  # type: ignore
    estimated_vocab = user_data.get("estimated_vocab", 0)
    if max_vocab is not None:
        estimated_vocab = min(estimated_vocab, max_vocab)

    # 3. estimated_vocab ± FREQ_BAND_HALF の帯域でフィルタ
    band_low = max(0, estimated_vocab - FREQ_BAND_HALF)
    band_high = estimated_vocab + FREQ_BAND_HALF
    if max_vocab is not None:
        band_high = min(band_high, max_vocab)
    candidates = [w for w in similar_words if band_low <= w["rank"] <= band_high]

    # 候補不足時は帯域を広げる
    if len(candidates) < count:
        band_low = max(0, estimated_vocab - FREQ_BAND_FALLBACK_HALF)
        band_high = estimated_vocab + FREQ_BAND_FALLBACK_HALF
        if max_vocab is not None:
            band_high = min(band_high, max_vocab)
        candidates = [w for w in similar_words if band_low <= w["rank"] <= band_high]

    # それでも足りなければ類似度上位からそのまま使う
    if len(candidates) < count:
        candidates = similar_words

    # 4. ランダムに count 語選出
    selected = random.sample(candidates, min(count, len(candidates)))
    words = [w["word"] for w in selected]

    print(
        f"get_session_words: topic={topic}, estimated_vocab={estimated_vocab}, "
        f"similar_words={len(similar_words)}, candidates={len(candidates)}, "
        f"selected={words}"
    )

    return words


def get_sentence_words(sentence: dict[str, Any]) -> list[str]:
    """例文の word_breakdown から全単語を重複なしで返す。"""
    seen: set[str] = set()
    words: list[str] = []
    for wb in sentence.get("word_breakdown", []):
        if not isinstance(wb, dict):
            continue
        w = str(wb.get("word", "")).strip()
        if w and w not in seen:
            seen.add(w)
            words.append(w)
    return words


def get_exposed_words(
    sentence: dict[str, Any],
    target_words: list[str] | None,
) -> list[str]:
    """例文内に実際に出現したターゲット語を単語ごとに1回だけ返す。"""
    if not target_words:
        return []

    target_word_set = set(target_words)
    return [w for w in get_sentence_words(sentence) if w in target_word_set]


def register_exposure(
    db: FirestoreClient,
    uid: str,
    words: list[str],
    *,
    create_new: bool = False,
) -> None:
    """露出による P 微増を適用する。

    Args:
        create_new: True なら UVM 未登録の単語も新規作成する（key_word 用）。
                    False なら既存単語のみ更新する。
    """
    now = time.time()
    batch = db.batch()
    uvm_ref = db.collection("users").document(uid).collection("uvm")
    wrote = 0

    for word, count in Counter(words).items():
        doc_ref = uvm_ref.document(word)
        doc = doc_ref.get()
        if doc.exists:
            data = doc.to_dict() or {}
            old_p = data.get("p", NEW_WORD_P)
            exposure_bonus = ALPHA_EXPOSURE * count
            batch.update(
                doc_ref,
                {
                    "p": max(P_MIN, min(P_MAX, old_p + exposure_bonus)),
                    "exposures": data.get("exposures", 0) + count,
                    "last_seen": now,
                },
            )
            wrote += count
        elif create_new:
            batch.set(
                doc_ref,
                {
                    "word": word,
                    "p": NEW_WORD_P,
                    "exposures": count,
                    "correct": 0,
                    "last_seen": now,
                    "last_result": None,
                },
            )
            wrote += count

    if wrote:
        batch.commit()
        print(f"register_exposure: uid={uid}, updated {wrote} word(s)")


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
    batch.commit()

    if freq_rank is not None:
        sync_vocab_count(db, uid, freq_rank)
