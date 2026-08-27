"""uvm.py の純粋関数（update_p / moving_avg / estimate_vocab）の golden を作る。

Go 移植（functions/go/internal/uvm）が同じ数値を出すことを固定する。
出力: golden.json（Go 側の TestAgainstPythonGolden が読む）
"""

import itertools
import json
import os
import random
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", ".."))

import uvm  # noqa: E402


class FakeDoc:
    """estimate_vocab が触るのは .id と .to_dict() だけ。"""

    def __init__(self, word, p):
        self.id = word
        self._p = p

    def to_dict(self):
        return {"p": self._p}


def update_p_cases():
    ps = [0.0, 0.1, 0.3, 0.5, 0.9, 0.99]
    attempts = [0, 1, 5, 20, 100]
    ranks = [None, 1, 10, 600, 3000, 10000]
    mults = [1.0, 0.5, 0.25, 0.1, 0.05, 0.025]
    out = []
    for p, correct, a, rank, m in itertools.product(ps, [True, False], attempts, ranks, mults):
        out.append({
            "p": p, "correct": correct, "quiz_attempts": a, "rank": rank,
            "hint_multiplier": m,
            "want": uvm.update_p(p, correct, a, rank, m),
        })
    return out


def moving_avg_cases():
    rng = random.Random(20260827)
    out = []
    for _ in range(200):
        n = rng.randint(0, 40)
        by_rank = {rng.randint(0, 300): round(rng.random(), 6) for _ in range(n)}
        center = rng.randint(0, 300)
        window = rng.choice([1, 5, 10, 20])
        out.append({
            "words_by_rank": {str(k): v for k, v in by_rank.items()},
            "center": center, "window": window,
            "want": uvm.moving_avg(by_rank, center, window),
        })
    return out


def estimate_vocab_cases():
    rng = random.Random(88)
    out = []
    for _ in range(300):
        n = rng.randint(0, 120)
        # 単語名は freq_rank のキーとして使うだけなので連番でよい
        freq_rank = {f"w{i}": i for i in range(0, 400)}
        docs = []
        seen = set()
        for _ in range(n):
            i = rng.randint(0, 399)
            if i in seen:
                continue
            seen.add(i)
            docs.append(FakeDoc(f"w{i}", round(rng.random(), 6)))
        # freq_rank に無い語も混ぜる（rank None の分岐）
        if rng.random() < 0.3:
            docs.append(FakeDoc("unknown-word", round(rng.random(), 6)))
        center = rng.choice([0, 0, rng.randint(0, 300)])
        out.append({
            "entries": [
                {"rank": freq_rank[d.id], "p": d._p}
                for d in docs if d.id in freq_rank
            ],
            "center": center,
            "want": uvm.estimate_vocab(docs, freq_rank, center),
        })
    return out


def main():
    golden = {
        "update_p": update_p_cases(),
        "moving_avg": moving_avg_cases(),
        "estimate_vocab": estimate_vocab_cases(),
    }
    path = os.path.join(os.path.dirname(__file__), "golden.json")
    with open(path, "w") as f:
        json.dump(golden, f, ensure_ascii=False)
    for k, v in golden.items():
        print(f"{k}: {len(v)} cases")


if __name__ == "__main__":
    main()
