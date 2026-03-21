"""UVM (User Vocabulary Model) コアロジック

ユーザーごとの語彙習得状態を管理する。
Firestore の users/{uid}/uvm/{word} コレクションに対して読み書きを行う。

【Firestore ドキュメント構造】
  users/{uid}/uvm/{word}:
    - p: float              — P(know) 確率 (0.01〜0.99)
    - quiz_attempts: int    — クイズ回答回数（α減衰に使用）
    - last_seen: float      — 最終閲覧 Unix timestamp
    - last_result: bool     — 直近の正誤

【主な機能】
  - トピック×語彙レベルに基づくセッション単語の選定 (get_session_words)
  - P(know) 確率の更新 (update_p)
  - クイズ結果からの一括更新 (batch_update_uvm)
  - 推定語彙数の算出 (estimate_vocab, sync_vocab_count)
"""

import math
import random
import time
from collections import Counter
from typing import Any, cast

from google.cloud.firestore_v1.base_document import DocumentSnapshot
from google.cloud.firestore_v1.client import Client as FirestoreClient

from embeddings import find_best_topic

# ---------------------------------------------------------------------------
# 定数
# ---------------------------------------------------------------------------
ALPHA_CORRECT_MAX = 0.35  # 正解時 α の初期値（quiz_attempts=0 時）
ALPHA_CORRECT_MIN = 0.02  # 正解時 α の下限
ALPHA_INCORRECT_MAX = 0.18  # 不正解時 α の初期値
ALPHA_INCORRECT_MIN = 0.02  # 不正解時 α の下限
ALPHA_DECAY_K = 0.08  # α 減衰係数
P_MIN = 0.0  # P の下限
P_MAX = 0.99  # P の上限
NEW_WORD_P = 0.02  # 新規単語の初期 P 値
ALPHA_EXPOSURE = 0.015  # 例文露出時の P 微増率
UNKNOWN_WORD_P = 0.3  # UVM 未登録語の prior P

# get_session_words 用: estimated_vocab 基準の頻度帯フィルタ幅
FREQ_BAND_HALF = 10  # 帯域: estimated_vocab ± 10
MAX_TOPIC_RETRY = 3  # 候補不足時のトピック再試行回数


def moving_avg(words_by_rank: dict[int, float], center: int, window: int = 10) -> float:
    """rank 周辺の平均習熟度を計算する（語彙境界推定用）。

    window = ±10 の範囲で P の平均を取る。
    UVM 未登録語には UNKNOWN_WORD_P を使用する。
    """
    total = 0.0
    for r in range(center - window, center + window + 1):
        total += words_by_rank.get(r, UNKNOWN_WORD_P)
    return total / (2 * window + 1)


def estimate_vocab(docs: list, freq_rank: dict[str, int], center: int = 0) -> int:
    """語彙境界（P ≈ 0.5 となる rank）を推定する。

    UVM ドキュメント群を rank でインデックスし、
    moving_avg が 0.5 を下回る最初の rank を返す。
    探索範囲は center ± 200。

    データがスパース（moving_avg が機能しにくい）場合は、
    P > 0.5 の語の最大 rank をフォールバックとして使う。

    Args:
        center: 探索中心（通常は現在の estimated_vocab）。
    """
    # docs から {rank: p} のマップを構築
    words_by_rank: dict[int, float] = {}
    weighted_ranks: list[tuple[float, int]] = []
    for doc in docs:
        p = (doc.to_dict() or {}).get("p", NEW_WORD_P)
        rank = freq_rank.get(doc.id)
        if rank is not None:
            words_by_rank[rank] = p
            weighted_ranks.append((p, rank))

    if not weighted_ranks:
        return 0

    # スパースデータ用フォールバック: P > 0.5 の語の最大 rank
    known_max_rank = max(
        (rank for p, rank in weighted_ranks if p > 0.5),
        default=0,
    )

    # center が未指定 (0) の場合は加重平均を使用
    if center <= 0:
        total_p = sum(p for p, _ in weighted_ranks)
        if total_p <= 0:
            return known_max_rank
        center = int(sum(p * rank for p, rank in weighted_ranks) / total_p)

    # center ± 200 の範囲で P < 0.5 となる rank を探索
    for r in range(center - 200, center + 201):
        avg = moving_avg(words_by_rank, r)
        if avg < 0.5:
            return max(known_max_rank, r, 0)

    return max(known_max_rank, center, 0)


def sync_estimated_vocab(
    db: FirestoreClient, uid: str, freq_rank: dict[str, int]
) -> None:
    """users/{uid} の estimated_vocab を効率的に更新する。

    現在の estimated_vocab を中心に ±200 の freq_rank 範囲の単語だけ
    UVM から取得して再計算する（全件取得を回避）。
    """
    user_ref = db.collection("users").document(uid)
    user_doc = cast("DocumentSnapshot", user_ref.get())
    current_estimate = 0
    if user_doc.exists:
        current_estimate = (user_doc.to_dict() or {}).get("estimated_vocab", 0)

    # freq_rank から探索範囲内の単語を抽出
    scan_low = max(0, current_estimate - 200)
    scan_high = current_estimate + 201
    target_words = [
        word for word, rank in freq_rank.items() if scan_low <= rank < scan_high
    ]

    # 対象単語の UVM ドキュメントだけ取得
    uvm_ref = user_ref.collection("uvm")
    refs = [uvm_ref.document(word) for word in target_words]
    docs = [snap for snap in db.get_all(refs) if snap.exists] if refs else []

    estimated = estimate_vocab(docs, freq_rank, center=current_estimate)
    user_ref.set({"estimated_vocab": estimated}, merge=True)


def update_p(p: float, correct: bool, quiz_attempts: int = 0) -> float:
    """P(know) を正誤に基づいて更新する。

    【更新式】
      正解時: α = ALPHA_CORRECT_MIN + (ALPHA_CORRECT_MAX - ALPHA_CORRECT_MIN) * exp(-k * quiz_attempts)
              p_new = p + α(1 - p)
      不正解: α = ALPHA_INCORRECT_MIN + (ALPHA_INCORRECT_MAX - ALPHA_INCORRECT_MIN) * exp(-k * quiz_attempts)
              p_new = p - α * p

    quiz_attempts が多いほど α が小さくなり、P 変化量が小さくなる（収束挙動）。
    結果は [P_MIN, P_MAX] にクリッピングして返す。
    """
    if correct:
        alpha = ALPHA_CORRECT_MIN + (ALPHA_CORRECT_MAX - ALPHA_CORRECT_MIN) * math.exp(
            -ALPHA_DECAY_K * quiz_attempts
        )
        p = p + alpha * (1 - p)
    else:
        alpha = ALPHA_INCORRECT_MIN + (
            ALPHA_INCORRECT_MAX - ALPHA_INCORRECT_MIN
        ) * math.exp(-ALPHA_DECAY_K * quiz_attempts)
        p = p - alpha * p
    return max(P_MIN, min(P_MAX, p))


def get_session_words(
    db: FirestoreClient,
    uid: str,
    freq_rank: dict[str, int],
    topic: str,
    count: int = 1,
    max_vocab: int | None = None,
    topics_pool: list[str] | None = None,
    estimated_vocab: int | None = None,
) -> tuple[list[str], str]:
    """key_word先行方式でセッション単語を選定する。

    【選定ロジック】
    1. freq_rank から estimated_vocab ± 10 の帯域内の単語を抽出
    2. 帯域内候補を priority 順に並べ、先頭から count 語を選出
    3. 選出した key_word の embedding と topic_embeddings のコサイン類似度で最適トピックを決定
    4. トピック指定がある場合はそのまま使用

    Args:
        db: Firestore クライアント
        uid: ユーザー UID
        freq_rank: {word: rank} — 頻出順位辞書
        topic: トピック文字列（空ならembeddingで自動選択）
        count: 選定する単語数（デフォルト 1）
        max_vocab: 語彙帯域の上限（free ティアでは 300）。None なら制限なし。
        topics_pool: トピック候補リスト（embedding でのトピック選択に使用）。
        estimated_vocab: 呼び出し元で取得済みの推定語彙数。省略時は Firestore から読む。

    Returns:
        (選定された単語のリスト, 使用されたトピック)
    """
    # ユーザーの推定語彙数を取得
    if estimated_vocab is None:
        user_doc = db.collection("users").document(uid).get()
        user_data = (user_doc.to_dict() or {}) if user_doc.exists else {}  # type: ignore
        estimated_vocab = user_data.get("estimated_vocab", 0)
    if max_vocab is not None and isinstance(estimated_vocab, int):
        estimated_vocab = min(estimated_vocab, max_vocab)

    # 帯域を計算
    band_low = max(0, estimated_vocab - FREQ_BAND_HALF)  # type: ignore
    band_high = estimated_vocab + FREQ_BAND_HALF  # type: ignore
    if max_vocab is not None:
        band_high = min(band_high, max_vocab)

    # --- Step 1: 帯域内の単語を抽出 ---
    band_words = [
        {"word": word, "rank": rank}
        for word, rank in freq_rank.items()
        if band_low <= rank <= band_high
    ]

    if not band_words:
        # 帯域内に候補がない場合は空を返す
        print(
            f"get_session_words: no band_words, estimated_vocab={estimated_vocab}, "
            f"band=[{band_low}, {band_high}]"
        )
        return [], topic or ""

    # --- Step 2: UVM の P 値を取得し、priority 順に count 語を選出 ---
    band_word_set = {w["word"] for w in band_words}
    uvm_ref = db.collection("users").document(uid).collection("uvm")
    refs = [uvm_ref.document(w) for w in band_word_set]
    p_map: dict[str, float] = {}
    if refs:
        snapshots = [ref.get() for ref in refs]
        for snap in snapshots:
            if snap.exists:
                p_val = (snap.to_dict() or {}).get("p")
                if isinstance(p_val, (int, float)):
                    p_map[snap.id] = float(p_val)

    def priority_key(candidate: dict[str, Any]) -> tuple[float, int, float]:
        effective_p = p_map.get(candidate["word"], NEW_WORD_P)
        distance = abs(candidate["rank"] - estimated_vocab)
        return (effective_p, distance, random.random())

    band_words.sort(key=priority_key)
    selected = band_words[:count]
    words = [w["word"] for w in selected]

    # --- Step 3: key_word の embedding からトピックを選択 ---
    if topic:
        chosen_topic = topic
    else:
        # 最初の key_word で最適トピックを決定
        chosen_topic = find_best_topic(words[0], topics_pool) or ""
        if not chosen_topic and topics_pool:
            chosen_topic = random.choice(topics_pool)

    print(
        f"get_session_words: topic={chosen_topic}, estimated_vocab={estimated_vocab}, "
        f"band_words={len(band_words)}, selected={words}"
    )

    return words, chosen_topic


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
) -> None:
    """露出による P 微増を適用する。未登録語は新規作成する。"""
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
            new_p = old_p
            for _ in range(count):
                new_p = new_p + ALPHA_EXPOSURE * (1 - new_p)
            batch.update(
                doc_ref,
                {
                    "p": max(P_MIN, min(P_MAX, new_p)),
                    "last_seen": now,
                },
            )
            wrote += count
        else:
            batch.set(
                doc_ref,
                {
                    "word": word,
                    "p": NEW_WORD_P,
                    "quiz_attempts": 0,
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
            quiz_attempts = data.get("quiz_attempts", 0)
            new_p = update_p(old_p, is_correct, quiz_attempts)
            batch.update(
                doc_ref,
                {
                    "p": new_p,
                    "quiz_attempts": quiz_attempts + 1,
                    "last_seen": now,
                    "last_result": is_correct,
                },
            )
        else:
            # --- 新規単語の作成（初めて見た単語） ---
            new_p = update_p(NEW_WORD_P, is_correct, 0)
            batch.set(
                doc_ref,
                {
                    "word": word,
                    "p": new_p,
                    "quiz_attempts": 1,
                    "last_seen": now,
                    "last_result": is_correct,
                },
            )
    batch.commit()

    if freq_rank is not None:
        sync_estimated_vocab(db, uid, freq_rank)
