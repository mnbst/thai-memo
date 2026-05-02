"""全問正解ユーザーの取りこぼしシミュレーション。

前提:
- 1日: 例文5回(各1語選出+露出) → 確認クイズ5問(同じ5語) → まとめクイズ5問(同じ5語から)
- 全問正解
- estimated_vocab は1日の終わりに sync
- freq_rank は 0〜max_rank の連続
"""

import math
import random

# --- uvm.py から定数コピー ---
ALPHA_CORRECT_MAX_TOP = 0.60
ALPHA_CORRECT_MAX_LOW = 0.30
ALPHA_CORRECT_MIN = 0.02
ALPHA_DECAY_K = 0.08
RANK_SCALE_REF = 600
P_MIN = 0.0
P_MAX = 0.99
NEW_WORD_P = 0.1
ALPHA_EXPOSURE = 0.10
UNKNOWN_WORD_P = 0.4
VOCAB_MAX_DELTA = 10
GAP_SCAN_DEPTH = 15
SCAN_AHEAD = 5

SENTENCES_PER_DAY = 5
REVIEW_QUIZ_COUNT = 5
SUMMARY_QUIZ_COUNT = 5


def update_p(p: float, correct: bool, quiz_attempts: int = 0, rank: int | None = None) -> float:
    scale = RANK_SCALE_REF / (rank + RANK_SCALE_REF) if rank is not None else 0.5
    if correct:
        alpha_max = ALPHA_CORRECT_MAX_LOW + (ALPHA_CORRECT_MAX_TOP - ALPHA_CORRECT_MAX_LOW) * scale
        alpha = ALPHA_CORRECT_MIN + (alpha_max - ALPHA_CORRECT_MIN) * math.exp(-ALPHA_DECAY_K * quiz_attempts)
        p = p + alpha * (1 - p)
    return min(max(p, P_MIN), P_MAX)


def moving_avg(words_by_rank: dict[int, float], center: int, window: int = 10, unk_p: float = UNKNOWN_WORD_P) -> float:
    total = sum(words_by_rank.get(r, unk_p) for r in range(center - window, center + window + 1))
    return total / (2 * window + 1)


def estimate_vocab(words_by_rank: dict[int, float], center: int, unk_p: float = UNKNOWN_WORD_P) -> int:
    known_max_rank = max((r for r, p in words_by_rank.items() if p > 0.5), default=0)
    for r in range(center - 50, center + 51):
        avg = moving_avg(words_by_rank, r, unk_p=unk_p)
        if avg < 0.42:
            return max(known_max_rank, r, 0)
    return max(known_max_rank, center, 0)


def select_words(p_map, estimated_vocab, depth, count, max_rank):
    scan_low = max(0, estimated_vocab - depth)
    scan_high = min(estimated_vocab + SCAN_AHEAD, max_rank)

    candidates = [r for r in range(scan_low, scan_high + 1)]
    zero_p = [r for r in candidates if r not in p_map or p_map[r] == 0.0]

    selected = []
    if zero_p:
        max_r = max(zero_p)
        weights = [math.sqrt(max_r - r + 1) for r in zero_p]
        remaining = list(zip(zero_p, weights))
        for _ in range(min(count, len(remaining))):
            ranks, ws = zip(*remaining)
            idx = random.choices(range(len(remaining)), weights=ws, k=1)[0]
            selected.append(remaining.pop(idx)[0])

    return selected


def simulate(max_rank: int = 300, days: int = 500, seed: int = 42,
             delta: int = VOCAB_MAX_DELTA, depth: int = GAP_SCAN_DEPTH,
             unk_p: float = UNKNOWN_WORD_P):
    random.seed(seed)
    p_map: dict[int, float] = {}
    quiz_attempts: dict[int, int] = {}
    estimated_vocab = 0
    VOCAB_MAX_DELTA_L = delta
    GAP_SCAN_DEPTH_L = depth
    UNKNOWN_WORD_P_L = unk_p

    print(f"{'Day':>4} {'EV':>4} {'Selected':>20} {'Gaps':>5}")
    print("-" * 60)

    for day in range(1, days + 1):
        # --- 例文5回: 各回1語選出 + 露出 ---
        day_words = select_words(p_map, estimated_vocab, GAP_SCAN_DEPTH_L, SENTENCES_PER_DAY, max_rank)

        for rank in day_words:
            p = p_map.get(rank, NEW_WORD_P)
            p = p + ALPHA_EXPOSURE * (1 - p)
            p_map[rank] = p

        # --- 確認クイズ5問: 同じ5語に正解 ---
        for rank in day_words:
            p = p_map.get(rank, NEW_WORD_P)
            attempts = quiz_attempts.get(rank, 0)
            p = update_p(p, correct=True, quiz_attempts=attempts, rank=rank)
            p_map[rank] = p
            quiz_attempts[rank] = attempts + 1

        # --- まとめクイズ5問: 同じ5語から選んで正解 ---
        summary_words = day_words[:SUMMARY_QUIZ_COUNT] if day_words else []
        for rank in summary_words:
            p = p_map.get(rank, NEW_WORD_P)
            attempts = quiz_attempts.get(rank, 0)
            p = update_p(p, correct=True, quiz_attempts=attempts, rank=rank)
            p_map[rank] = p
            quiz_attempts[rank] = attempts + 1

        # --- sync estimated_vocab ---
        raw = estimate_vocab(p_map, center=estimated_vocab, unk_p=UNKNOWN_WORD_P_L)
        delta_raw = raw - estimated_vocab
        clamped = max(-VOCAB_MAX_DELTA_L, min(VOCAB_MAX_DELTA_L, delta_raw))
        estimated_vocab = max(0, estimated_vocab + clamped)

        # --- 取りこぼし集計 ---
        gaps = [r for r in range(0, estimated_vocab) if r not in p_map or p_map[r] == 0.0]

        if day <= 20 or day % 25 == 0 or day == days:
            print(f"{day:>4} {estimated_vocab:>4} {str(day_words):>20} {len(gaps):>5}")

    total_gaps = [r for r in range(0, estimated_vocab) if r not in p_map or p_map[r] == 0.0]
    print(f"\n=== 最終結果 (day {days}) ===")
    print(f"estimated_vocab: {estimated_vocab}")
    print(f"学習済み語数: {len([r for r in p_map if p_map[r] > 0])}")
    print(f"取りこぼし数: {len(total_gaps)}")
    if total_gaps:
        print(f"取りこぼし ranks (先頭20): {total_gaps[:20]}")


if __name__ == "__main__":
    for delta, depth, unk_p in [
        (3, 30, 0.4),
        (3, 25, 0.4),
        (3, 20, 0.4),
        (3, 15, 0.4),
        (3, 10, 0.4),
    ]:
        print(f"\n{'='*60}")
        print(f"DELTA={delta}, DEPTH={depth}, UNK_P={unk_p}")
        print(f"{'='*60}")
        simulate(delta=delta, depth=depth, unk_p=unk_p)
