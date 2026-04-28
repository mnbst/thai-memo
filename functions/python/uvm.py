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
  - テーマ×語彙レベルに基づくセッション単語の選定 (get_session_words)
  - P(know) 確率の更新 (update_p)
  - クイズ結果からの一括更新 (batch_update_uvm)
  - 語彙スコアの算出 (estimate_vocab, sync_vocab_count)
"""

import json
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
ALPHA_CORRECT_MAX_TOP = 0.50  # rank≈1（高頻度語）の正解α上限: 1問正解でP=0.1→0.55
ALPHA_CORRECT_MAX_LOW = 0.20  # 高rank（低頻度語）の正解α下限: 3問正解でP>0.5
ALPHA_CORRECT_MIN = 0.02  # 正解時 α の下限（quiz_attempts 大時の収束値）
ALPHA_INCORRECT_MAX_TOP = 0.28  # rank≈1 の不正解α上限
ALPHA_INCORRECT_MAX_LOW = 0.08  # 高rank の不正解α下限
ALPHA_INCORRECT_MIN = 0.02  # 不正解時 α の下限
ALPHA_DECAY_K = 0.08  # α 減衰係数（quiz_attempts による α 減衰速度）
RANK_SCALE_REF = (
    600  # このrankでalpha_maxが上限・下限の中間値になる（rank>3000で3問正解挙動）
)
P_MIN = 0.0  # P の下限
P_MAX = 0.99  # P の上限
NEW_WORD_P = 0.1  # 新規単語の初期 P 値
ALPHA_EXPOSURE = 0.03  # 例文露出時の P 微増率
UNKNOWN_WORD_P = 0.3  # UVM 未登録語の prior P

# get_session_words 用: estimated_vocab 基準の頻度帯
FREQ_BAND_HALF = 15  # 通常帯域の半幅: estimated_vocab ± FREQ_BAND_HALF
VOCAB_MAX_DELTA = 10  # 1回の sync で estimated_vocab が動ける最大幅
GAP_SCAN_DEPTH = 100  # ギャップスキャン深度: band_boundary からさらに後方へのスキャン幅


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

    # center ± 50 の範囲で P < 0.5 となる rank を探索
    for r in range(center - 50, center + 51):
        avg = moving_avg(words_by_rank, r)
        if avg < 0.5:
            return max(known_max_rank, r, 0)

    return max(known_max_rank, center, 0)


def sync_estimated_vocab(
    db: FirestoreClient, uid: str, freq_rank: dict[str, int]
) -> None:
    """users/{uid} の estimated_vocab を効率的に更新する。

    現在の estimated_vocab を中心に ±50 の freq_rank 範囲の単語だけ
    UVM から取得して再計算する（全件取得を回避）。
    """
    user_ref = db.collection("users").document(uid)
    user_doc = cast("DocumentSnapshot", user_ref.get())
    current_estimate = 0
    if user_doc.exists:
        current_estimate = (user_doc.to_dict() or {}).get("estimated_vocab", 0)

    # freq_rank から探索範囲内の単語を抽出
    scan_low = max(0, current_estimate - 50)
    scan_high = current_estimate + 51
    target_words = [
        word for word, rank in freq_rank.items() if scan_low <= rank < scan_high
    ]

    # 対象単語の UVM ドキュメントだけ取得
    uvm_ref = user_ref.collection("uvm")
    refs = [uvm_ref.document(word) for word in target_words]
    docs = [snap for snap in db.get_all(refs) if snap.exists] if refs else []

    raw = estimate_vocab(docs, freq_rank, center=current_estimate)
    delta = raw - current_estimate
    clamped_delta = max(-VOCAB_MAX_DELTA, min(VOCAB_MAX_DELTA, delta))
    estimated = max(0, current_estimate + clamped_delta)
    user_ref.set({"estimated_vocab": estimated}, merge=True)


def update_p(
    p: float,
    correct: bool,
    quiz_attempts: int = 0,
    rank: int | None = None,
    hint_multiplier: float = 1.0,
) -> float:
    """P(know) を正誤に基づいて更新する。

    【更新式】
      rank に応じて alpha_max をスケーリングする。
        scale = RANK_SCALE_REF / (rank + RANK_SCALE_REF)  ← rank が低いほど 1 に近い
        alpha_max = ALPHA_*_MAX_LOW + (ALPHA_*_MAX_TOP - ALPHA_*_MAX_LOW) * scale
      正解時: α = ALPHA_CORRECT_MIN + (alpha_max - ALPHA_CORRECT_MIN) * exp(-k * quiz_attempts)
              p_new = p + α(1 - p)
      不正解: α = ALPHA_INCORRECT_MIN + (alpha_max - ALPHA_INCORRECT_MIN) * exp(-k * quiz_attempts)
              p_new = p - α * p

    【rank による挙動（quiz_attempts=0, p=0.1 から）】
      rank ≈ 1  (scale≈1, α≈0.50): 正解1問で P > 0.5
      rank ≈ 600 (scale=0.5, α=0.35): 正解2問で P > 0.5
      rank > 3000 (scale<0.17, α<0.25): 正解3問で P > 0.5

    rank=None の場合は scale=0.5（中間値）を使用する。
    quiz_attempts が多いほど α が小さくなり、P 変化量が小さくなる（収束挙動）。
    結果は [P_MIN, P_MAX] にクリッピングして返す。
    """
    scale = RANK_SCALE_REF / (rank + RANK_SCALE_REF) if rank is not None else 0.5
    if correct:
        alpha_max = (
            ALPHA_CORRECT_MAX_LOW
            + (ALPHA_CORRECT_MAX_TOP - ALPHA_CORRECT_MAX_LOW) * scale
        )
        alpha = ALPHA_CORRECT_MIN + (alpha_max - ALPHA_CORRECT_MIN) * math.exp(
            -ALPHA_DECAY_K * quiz_attempts
        )
        p = p + alpha * hint_multiplier * (1 - p)
    else:
        alpha_max = (
            ALPHA_INCORRECT_MAX_LOW
            + (ALPHA_INCORRECT_MAX_TOP - ALPHA_INCORRECT_MAX_LOW) * scale
        )
        alpha = ALPHA_INCORRECT_MIN + (alpha_max - ALPHA_INCORRECT_MIN) * math.exp(
            -ALPHA_DECAY_K * quiz_attempts
        )
        p = p - alpha * hint_multiplier * p
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
    """ギャップ優先方式でセッション単語を選定する。

    【選定ロジック】
    1. rank < (estimated_vocab - FREQ_BAND_HALF) の範囲で UVM未登録 or P=0 の語（ギャップ語）を探す
       → あれば：そこからランダム選出（高頻度の語彙ギャップを優先的に埋める）
       → なければ：estimated_vocab ± FREQ_BAND_HALF の帯域からランダム選出
    2. 選出した key_word の embedding と topic_embeddings のコサイン類似度で最適テーマを決定
    3. テーマ指定がある場合はそのまま使用

    Args:
        db: Firestore クライアント
        uid: ユーザー UID
        freq_rank: {word: rank} — 頻出順位辞書
        topic: テーマ文字列（空ならembeddingで自動選択）
        count: 選定する単語数（デフォルト 1）
        max_vocab: 語彙帯域の上限（free ティアでは 300）。None なら制限なし。
        topics_pool: テーマ候補リスト（embedding でのテーマ選択に使用）。
        estimated_vocab: 呼び出し元で取得済みの語彙スコア。省略時は Firestore から読む。

    Returns:
        (選定された単語のリスト, 使用されたテーマ)
    """
    # ユーザーの語彙スコアを取得
    if estimated_vocab is None:
        user_doc = db.collection("users").document(uid).get()
        user_data = (user_doc.to_dict() or {}) if user_doc.exists else {}  # type: ignore
        estimated_vocab = user_data.get("estimated_vocab", 0)
    if max_vocab is not None and isinstance(estimated_vocab, int):
        estimated_vocab = min(estimated_vocab, max_vocab)

    band_boundary = max(0, estimated_vocab - FREQ_BAND_HALF)  # type: ignore
    band_high = estimated_vocab + FREQ_BAND_HALF  # type: ignore
    if max_vocab is not None:
        band_high = min(band_high, max_vocab)

    selected: list[dict[str, Any]] = []

    # --- Step 1: ギャップスキャン (rank < band_boundary で未登録 or P=0) ---
    gap_scan_low = max(0, band_boundary - GAP_SCAN_DEPTH)
    if gap_scan_low < band_boundary:
        gap_candidates = [
            {"word": word, "rank": rank}
            for word, rank in freq_rank.items()
            if gap_scan_low <= rank < band_boundary and len(word) >= 2
        ]
        if gap_candidates:
            gap_word_set = {w["word"] for w in gap_candidates}
            uvm_ref = db.collection("users").document(uid).collection("uvm")
            refs = [uvm_ref.document(w) for w in gap_word_set]
            gap_p_map: dict[str, float] = {}
            for snap in db.get_all(refs):
                if snap.exists:
                    p_val = (snap.to_dict() or {}).get("p")
                    if isinstance(p_val, (int, float)):
                        gap_p_map[snap.id] = float(p_val)

            zero_p_candidates = [
                w
                for w in gap_candidates
                if w["word"] not in gap_p_map or gap_p_map[w["word"]] == 0.0
            ]
            if zero_p_candidates:
                selected = random.sample(
                    zero_p_candidates, min(count, len(zero_p_candidates))
                )

    # --- Step 2: ギャップなし → ±FREQ_BAND_HALF 帯域から優先選出 ---
    # 優先順位: UVM未登録 > P最小 > ランダム
    if not selected:
        band_words = [
            {"word": word, "rank": rank}
            for word, rank in freq_rank.items()
            if band_boundary <= rank <= band_high and len(word) >= 2
        ]
        if not band_words:
            print(
                f"get_session_words: no band_words, estimated_vocab={estimated_vocab}, "
                f"band=[{band_boundary}, {band_high}]"
            )
            return [], topic or ""

        # 帯域単語の UVM を一括取得
        band_word_set = {w["word"] for w in band_words}
        uvm_ref = db.collection("users").document(uid).collection("uvm")
        refs = [uvm_ref.document(w) for w in band_word_set]
        band_p_map: dict[str, float] = {}
        for snap in db.get_all(refs):
            if snap.exists:
                p_val = (snap.to_dict() or {}).get("p")
                if isinstance(p_val, (int, float)):
                    band_p_map[snap.id] = float(p_val)

        # 未登録 or P=0 を最優先、なければ P が低いほど選ばれやすい重み付きランダム
        zero_p = [
            w
            for w in band_words
            if w["word"] not in band_p_map or band_p_map[w["word"]] == 0.0
        ]
        if zero_p:
            selected = random.sample(zero_p, min(count, len(zero_p)))
        else:
            remaining = list(band_words)
            remaining_weights = [
                max(0.0, 1.0 - band_p_map.get(w["word"], 0.0))
                for w in remaining
            ]
            for _ in range(min(count, len(remaining))):
                if sum(remaining_weights) <= 0:
                    index = random.randrange(len(remaining))
                else:
                    index = random.choices(
                        range(len(remaining)),
                        weights=remaining_weights,
                        k=1,
                    )[0]
                selected.append(remaining.pop(index))
                remaining_weights.pop(index)

    words = [w["word"] for w in selected]

    # --- Step 3: key_word の embedding からテーマを選択 ---
    if topic:
        chosen_topic = topic
    else:
        chosen_topic = (
            find_best_topic(words[0], topics_pool, top_k=5, threshold=0.545) or ""
        )
        if not chosen_topic and topics_pool:
            chosen_topic = random.choice(topics_pool)

    print(
        json.dumps(
            {
                "message": "get_session_words",
                "topic": chosen_topic,
                "estimated_vocab": estimated_vocab,
                "gap_scan": [gap_scan_low, band_boundary],
                "band": [band_boundary, band_high],
                "selected": words,
            }
        )
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
    target_words: list[str] | None = None,
) -> None:
    """露出による P 微増を適用する。

    - 登録済み語: P を ALPHA_EXPOSURE 分微増
    - 未登録語: target_words に含まれる場合のみ新規作成（P=NEW_WORD_P で登録）
    """
    now = time.time()
    batch = db.batch()
    uvm_ref = db.collection("users").document(uid).collection("uvm")
    target_word_set = set(target_words) if target_words else set()
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
        elif word in target_word_set:
            # key_word として選出された未登録語は新規作成
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
            wrote += 1

    if wrote:
        batch.commit()
        print(f"register_exposure: uid={uid}, updated {wrote} word(s)")


LEARNING_CORRECT_MULTIPLIER = 0.1
SENTENCE_REVIEW_CORRECT_MULTIPLIER = 0.1


def batch_update_uvm(
    db: FirestoreClient,
    uid: str,
    results: list[dict[str, Any]],
    freq_rank: dict[str, int] | None = None,
    quiz_type: str = "",
) -> None:
    """クイズ/例文の正誤結果をもとに UVM を一括更新する。

    既存の UVM ドキュメントがあれば P を更新、なければ新規作成する。

    Args:
        db: Firestore クライアント
        uid: ユーザー UID
        results: [{"word": str, "is_correct": bool}, ...] — 各単語の正誤
        quiz_type: "learning" の場合、正解時の α を LEARNING_CORRECT_MULTIPLIER で減衰
    """
    now = time.time()
    batch = db.batch()
    uvm_ref = db.collection("users").document(uid).collection("uvm")

    # 全単語のドキュメントを一括取得
    words = [r["word"] for r in results]
    refs = [uvm_ref.document(word) for word in words]
    docs_map: dict[str, Any] = {}
    for snap in db.get_all(refs):
        if snap.exists:
            docs_map[snap.id] = snap.to_dict() or {}

    for r in results:
        word = r["word"]
        is_correct = r["is_correct"]
        doc_ref = uvm_ref.document(word)

        rank = freq_rank.get(word) if freq_rank else None
        hint_level_raw = r.get("hint_level")
        hint_level = (
            int(hint_level_raw) if isinstance(hint_level_raw, (int, float)) else 0
        )
        hint_multiplier = 1.0 if hint_level == 0 else (0.5 if hint_level == 1 else 0.25)
        if quiz_type == "learning" and is_correct:
            hint_multiplier *= LEARNING_CORRECT_MULTIPLIER
        if r.get("sentence_reviewed") is True and is_correct:
            hint_multiplier *= SENTENCE_REVIEW_CORRECT_MULTIPLIER
        if word in docs_map:
            # --- 既存単語の更新 ---
            data = docs_map[word]
            old_p = data.get("p", NEW_WORD_P)
            quiz_attempts = data.get("quiz_attempts", 0)
            new_p = update_p(old_p, is_correct, quiz_attempts, rank, hint_multiplier)
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
            new_p = update_p(NEW_WORD_P, is_correct, 0, rank, hint_multiplier)
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
