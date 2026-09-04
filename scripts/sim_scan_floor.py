"""key_word 帯域の後方下限（GapScanDepth）と Firestore 読み取り数のトレードオフ。

`functions/go/internal/uvm` の式をそのまま写して 1 人のユーザーを日次で回す。
毎回の key_word 選定は帯域内の全候補の UVM doc を GetAll するので、
**候補数 = 1 回あたりの読み取り数**。下限を入れると読み取りは減るが、
境界より下へ流れた語が二度と候補に入らず取りこぼしが増える。

  python3 scripts/sim_scan_floor.py            # 既定（365日 x 10試行）
  python3 scripts/sim_scan_floor.py --days 90 --trials 20
"""

import argparse
import math
import random
from collections import Counter

# --- functions/go/internal/uvm/model.go の定数 ---
ALPHA_CORRECT_MAX_TOP = 0.60
ALPHA_CORRECT_MAX_LOW = 0.30
ALPHA_CORRECT_MIN = 0.02
ALPHA_INCORRECT_MAX_TOP = 0.28
ALPHA_INCORRECT_MAX_LOW = 0.08
ALPHA_INCORRECT_MIN = 0.02
ALPHA_DECAY_K = 0.08
RANK_SCALE_REF = 600
P_MIN, P_MAX = 0.0, 0.99
NEW_WORD_P = 0.1
UNKNOWN_WORD_P = 0.4
VOCAB_MAX_DELTA = 3
VOCAB_CUTOFF_P = 0.42
VOCAB_CUTOFF_P_TESTED = 0.30
MAX_VOCAB_FLOOR = 600
ALPHA_EXPOSURE = 0.10          # exposure.go
EXPOSURE_CAP = UNKNOWN_WORD_P  # exposure.go
SCAN_BAND_WIDTH = 50           # session.go
SCAN_BAND_DECAY = 2
SCAN_AHEAD_MIN = 8

# --- シミュレーション条件（Go 版 sim_floor_test.go と同じ）---
VOCAB_SIZE = 4000
GEN_PER_DAY = 5
QUIZ_PER_DAY = 5
OTHER_WORDS = 7
DAILY_DECAY = 0.001


def build_freq_rank() -> dict[str, int]:
    """rank 1..VOCAB_SIZE の擬似語彙。約30%を1文字語にして len>=2 フィルタを再現する。

    Knuth 乗算ハッシュで rank と無相関に散らす（rank%n だと帯域が偏る）。
    """
    fr, single = {}, 0x4E00
    for r in range(1, VOCAB_SIZE + 1):
        if (r * 2654435761 % (1 << 32)) % 100 < 30:
            fr[chr(single)] = r
            single += 1
        else:
            fr[f"w{r:04d}"] = r
    return fr


def update_p(p, correct, attempts, rank, mult=1.0):
    scale = RANK_SCALE_REF / (rank + RANK_SCALE_REF) if rank is not None else 0.5
    decay = math.exp(-ALPHA_DECAY_K * attempts)
    if correct:
        amax = ALPHA_CORRECT_MAX_LOW + (ALPHA_CORRECT_MAX_TOP - ALPHA_CORRECT_MAX_LOW) * scale
        p += (ALPHA_CORRECT_MIN + (amax - ALPHA_CORRECT_MIN) * decay) * mult * (1 - p)
    else:
        amax = ALPHA_INCORRECT_MAX_LOW + (ALPHA_INCORRECT_MAX_TOP - ALPHA_INCORRECT_MAX_LOW) * scale
        p -= (ALPHA_INCORRECT_MIN + (amax - ALPHA_INCORRECT_MIN) * decay) * mult * p
    return min(max(p, P_MIN), P_MAX)


def exposure_p(old, count):
    p = old
    for _ in range(count):
        p += ALPHA_EXPOSURE * (1 - p)
    return min(max(p, P_MIN), P_MAX)


def capped_exposure_p(old, count):
    return min(exposure_p(old, count), max(old, EXPOSURE_CAP))


def moving_avg(p_by_rank, center, window=10):
    total = sum(p_by_rank.get(r, UNKNOWN_WORD_P) for r in range(center - window, center + window + 1))
    return total / (2 * window + 1)


def estimate_vocab(entries, center, tested_vocab=0):
    """entries: [(rank, p)]。model.go:EstimateVocabTested の写し（tested=0 なら EstimateVocab）。"""
    if not entries:
        return 0
    p_by_rank = {}
    known_max = 0
    for r, p in entries:
        p_by_rank[r] = p
        if p > 0.5 and r > known_max:
            known_max = r
    for r in range(center - 50, center + 51):
        cutoff = VOCAB_CUTOFF_P_TESTED if 0 < tested_vocab and r <= tested_vocab else VOCAB_CUTOFF_P
        if moving_avg(p_by_rank, r) < cutoff:
            return max(known_max, max(r, 0))
    return max(known_max, max(center, 0))


def scan_band(ev, width=SCAN_BAND_WIDTH, decay=SCAN_BAND_DECAY, ahead_min=SCAN_AHEAD_MIN):
    ahead = max(width - ev / decay, ahead_min)
    return 0, ev + int(ahead)


def p_know(rank, true_vocab, scale=60.0):
    return 1 / (1 + math.exp((rank - true_vocab) / scale))


class User:
    """Firestore doc をメモリに置いただけのユーザー。判断ロジックは上の関数群。"""

    def __init__(self, floor, depth, frac, rng, tested_vocab=0, sample=0, window=0,
                 tested_floor=False, min_band=0, ahead=None):
        self.p = {}          # word -> p
        self.attempts = {}   # word -> quiz_attempts
        self.picked = set()
        self.ev = max(floor, tested_vocab)
        self.tested = tested_vocab
        self.floor = floor
        self.depth = depth   # 後方の固定下限（None なら無制限）
        self.sample = sample # 帯域は開いたまま、読む候補数だけ上限する
        self.window = window # 帯域は開いたまま、後方を幅 window の窓で巡回する
        self.tested_floor = tested_floor  # 語彙テストの測定値を後方の下限にする
        self.min_band = min_band  # 帯がこの幅を割らないところまで下限を戻す
        self.ahead = ahead or (SCAN_BAND_WIDTH, SCAN_BAND_DECAY, SCAN_AHEAD_MIN)
        self.above = 0  # 境界より上から選ばれた key_word の数
        self.key_ranks = []  # 選ばれた key_word の rank（境界との差を見る）
        self.day_words = []  # 日ごとの key_word（同日被りを見る）
        self.frac = frac     # ev に比例させる深さ（None なら固定のみ）
        self.rng = rng
        self.reads = 0
        self.selections = 0
        self.key_hits = Counter()

    def band(self):
        low, high = scan_band(self.ev, *self.ahead)
        d = None
        if self.depth is not None:
            d = self.depth
        if self.frac is not None:
            d = max(d or 0, int(self.frac * self.ev))
        if d is not None:
            low = max(0, self.ev - d)
        if self.tested_floor and self.tested > 0:
            # 受験者は測定値より下を既知とみなし、走査しない。
            low = max(low, min(self.tested, high))
        if self.min_band:
            # 測定が過大だと帯が数語に潰れて同じ語を出し続けるので、幅を保証する。
            low = min(low, max(0, high - self.min_band + 1))
        return low, high

    def select_key_word(self, by_rank):
        low, high = self.band()
        cands = [(r, by_rank[r]) for r in range(low, high + 1)
                 if r in by_rank and len(by_rank[r]) >= 2]
        if self.window and self.ev > self.window:
            # 後方は幅 window の窓を毎回ずらして巡回し、前方は常に見る。
            off = (self.selections * self.window) % max(1, self.ev)
            wl, wh = off, off + self.window - 1
            cands = [c for c in cands if wl <= c[0] <= wh or c[0] >= self.ev]
        if self.sample and len(cands) > self.sample:
            cands = sorted(self.rng.sample(cands, self.sample))
        if not cands:
            return None
        self.reads += len(cands)   # fetchP の GetAll
        self.selections += 1
        zero = [c for c in cands if self.p.get(c[1], 0.0) == 0.0]
        if zero:
            max_rank = max(r for r, _ in zero)
            weights = [math.sqrt(max_rank - r + 1) for r, _ in zero]
            pool = zero
        else:
            weights = [max(0.0, 1.0 - self.p.get(w, 0.0)) for _, w in cands]
            pool = cands
        if sum(weights) <= 0:
            return pool[self.rng.randrange(len(pool))]
        return self.rng.choices(pool, weights=weights, k=1)[0]

    def register_exposure(self, words, target):
        for w, n in Counter(words).items():
            if w in self.p:
                self.p[w] = capped_exposure_p(self.p[w], n)
            elif w == target:
                self.p[w] = NEW_WORD_P

    def sync_estimated_vocab(self, rank_of):
        low, high = max(0, self.ev - 50), self.ev + 51
        entries = [(rank_of[w], p) for w, p in self.p.items() if low <= rank_of[w] < high]
        raw = estimate_vocab(entries, self.ev, self.tested)
        delta = max(-VOCAB_MAX_DELTA, min(VOCAB_MAX_DELTA, raw - self.ev))
        self.ev = max(max(0, self.ev + delta), self.floor)


def run(seed, true_vocab, floor, days, depth, frac, tested_vocab=0, sample=0, window=0,
        tested_floor=False, min_band=0, ahead=None):
    rng = random.Random(seed)
    fr = build_freq_rank()
    rank_of = fr
    by_rank = {r: w for w, r in fr.items()}
    u = User(floor, depth, frac, rng, tested_vocab, sample, window, tested_floor, min_band, ahead)

    for _ in range(days):
        today = []
        for _ in range(GEN_PER_DAY):
            kw = u.select_key_word(by_rank)
            if kw is None:
                continue
            r, w = kw
            today.append(w)
            if r > u.ev:
                u.above += 1
            u.key_ranks.append((u.ev, r))
            u.picked.add(w)
            u.key_hits[w] += 1
            lo, hi = scan_band(u.ev, *u.ahead)
            words = [w] + [by_rank[x] for x in
                           (lo + rng.randrange(max(1, hi - lo + 1)) for _ in range(OTHER_WORDS))
                           if x in by_rank]
            u.register_exposure(words, w)
            u.sync_estimated_vocab(rank_of)

        u.day_words.append(today)
        for w, _ in sorted(u.p.items(), key=lambda kv: (kv[1], kv[0]))[:QUIZ_PER_DAY]:
            r = rank_of[w]
            correct = rng.random() < p_know(r, true_vocab)
            u.p[w] = update_p(u.p[w], correct, u.attempts.get(w, 0), r)
            u.attempts[w] = u.attempts.get(w, 0) + 1
        u.sync_estimated_vocab(rank_of)

        for w in u.p:
            u.p[w] = max(0.0, u.p[w] - DAILY_DECAY)

    selectable = missed = unknown_sel = unknown_missed = 0
    for r in range(1, u.ev + 1):
        w = by_rank.get(r)
        if w is None or len(w) < 2:
            continue
        selectable += 1
        never_seen = w not in u.picked and w not in u.p
        if never_seen:
            missed += 1
        # 受験者が測定値より下を既知とするなら、そこは取りこぼしに数えない。
        if r > tested_vocab:
            unknown_sel += 1
            if never_seen:
                unknown_missed += 1
    dup = sum(u.key_hits.values()) / max(1, len(u.key_hits))
    # 直近30日: 1日5生成のうち何語がユニークか（同日被りの直接指標）
    tail_days = u.day_words[-30:] or u.day_words
    uniq_per_day = sum(len(set(d)) for d in tail_days) / max(1, len(tail_days))
    # 直近30日ぶんの key_word で「境界との差」を見る（初期の帯に引きずられないように）
    tail = u.key_ranks[-30 * GEN_PER_DAY:] or u.key_ranks
    gaps = sorted(ev - r for ev, r in tail)
    return {
        "ev": u.ev,
        "selectable": selectable,
        "missed_rate": missed / selectable * 100 if selectable else 0.0,
        "unknown_missed_rate": unknown_missed / unknown_sel * 100 if unknown_sel else 0.0,
        "gap": gaps[len(gaps) // 2] if gaps else 0.0,
        "dup": dup,
        "uniq_per_day": uniq_per_day,
        "above_rate": u.above / max(1, len(u.key_ranks)) * 100,
        "reads": u.reads / max(1, u.selections),
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--days", type=int, default=365)
    ap.add_argument("--trials", type=int, default=10)
    ap.add_argument("--depths", default="150,250,400,600",
                    help="固定下限の深さ（カンマ区切り）")
    ap.add_argument("--fracs", default="0.5,0.75",
                    help="ev 比例の深さ（カンマ区切り、空で無効）")
    ap.add_argument("--cases", default="350:300,800:600,1500:600",
                    help="真値:申告floor[:測定値] のカンマ区切り（測定値を書くと受験者）")
    ap.add_argument("--samples", default="", help="読取上限（カンマ区切り）")
    ap.add_argument("--windows", default="", help="巡回窓の幅（カンマ区切り）")
    ap.add_argument("--tested-floors", default="",
                    help="測定値を下限にする案の深さ（カンマ区切り。t50 のように書く）")
    ap.add_argument("--min-bands", default="",
                    help="測定値下限に最低帯幅を足す案（カンマ区切り。下限は測定値）")
    ap.add_argument("--tested", action="store_true",
                    help="語彙テスト受験者として回す（測定値=真値、EstimateVocabTested 経路）")
    args = ap.parse_args()

    configs = [("無制限(現行)", None, None, 0, 0)] + \
              [(d, int(d), None, 0, 0) for d in args.depths.split(",") if d] + \
              [(f"{float(f):.2f}ev", None, float(f), 0, 0) for f in args.fracs.split(",") if f] + \
              [(f"抽出{k}", None, None, int(k), 0) for k in args.samples.split(",") if k] + \
              [(f"巡回窓{w}", None, None, 0, int(w)) for w in args.windows.split(",") if w]
    configs = [c + (False, 0) for c in configs] + \
              [(f"測定値+下限{d}", int(d), None, 0, 0, True, 0)
               for d in args.tested_floors.split(",") if d] + \
              [(f"測定値+最低帯{b}", None, None, 0, 0, True, int(b))
               for b in args.min_bands.split(",") if b]

    cases = []
    for c in args.cases.split(","):
        parts = [int(x) for x in c.split(":")]
        cases.append((parts + [0])[:3] if len(parts) < 3 else parts)
    for true_vocab, floor, measured in cases:
        who = f"測定{measured}" if measured else ("測定=真値" if args.tested else "未受験")
        print(f"\n真値{true_vocab}・申告{floor}・{who}・{args.days}日（{args.trials}試行平均）")
        print(f"{'後方下限':<14}{'境界':>6}{'境界との差':>9}{'未知取りこぼし':>12}"
              f"{'重複率':>8}{'新語/日(5中)':>12}{'平均読取数':>10}")
        for label, depth, frac, sample, window, tfloor, mband in configs:
            acc = {k: 0.0 for k in ("ev", "selectable", "missed_rate",
                                    "unknown_missed_rate", "gap", "dup",
                                    "uniq_per_day", "reads")}
            for t in range(args.trials):
                tested = measured or (true_vocab if args.tested else 0)
                for k, v in run(t, true_vocab, floor, args.days, depth, frac,
                                tested, sample, window, tfloor, mband).items():
                    acc[k] += v / args.trials
            print(f"{label:<16}{acc['ev']:>6.0f}{acc['gap']:>9.0f}"
                  f"{acc['unknown_missed_rate']:>12.1f}%{acc['dup']:>8.2f}"
                  f"{acc['uniq_per_day']:>12.2f}{acc['reads']:>10.0f}")


if __name__ == "__main__":
    main()
