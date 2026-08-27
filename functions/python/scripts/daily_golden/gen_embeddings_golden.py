"""embeddings.py の数値計算を Python 実装から書き出す。

GCS を介さずに済むよう、合成した小さな embedding 行列で比べる。
Go 版 internal/embeddings との差分テストに使う。
出力先: functions/python/scripts/daily_golden/embeddings_golden.json
"""

import base64
import io
import json
import os
import random
import sys

import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", ".."))

import embeddings as em  # noqa: E402

DIM = 64
N = 200


def main() -> None:
    rng = np.random.default_rng(20260827)
    # 実データに近い分布（正負が混ざり、ノルムが1付近）にする
    matrix = rng.standard_normal((N, DIM)).astype(np.float32)
    matrix /= np.linalg.norm(matrix, axis=1, keepdims=True)
    # 同義語ペアを意図的に作る（重複除去の閾値を踏ませるため）
    for i in range(0, 40, 2):
        matrix[i + 1] = matrix[i] + rng.standard_normal(DIM).astype(np.float32) * 0.05
        matrix[i + 1] /= np.linalg.norm(matrix[i + 1])
    # ゼロベクトルも1本混ぜる
    matrix[N - 1] = np.zeros(DIM, dtype=np.float32)

    words = [{"word": f"w{i}", "rank": i + 1} for i in range(N)]

    buf = io.BytesIO()
    np.save(buf, matrix, allow_pickle=False)
    npy_b64 = base64.b64encode(buf.getvalue()).decode()

    # Python 側のグローバルへ直接差し込む（GCS を叩かせない）
    em._embeddings = matrix
    em._words = words
    em._word_to_idx = {w["word"]: i for i, w in enumerate(words)}

    # --- cosine_similarity ---
    pyrng = random.Random(20260827)
    cos_cases = []
    for _ in range(3000):
        i = pyrng.randrange(N)
        j = pyrng.randrange(N)
        cos_cases.append({
            "a": i, "b": j,
            "sim": em.cosine_similarity(matrix[i], matrix[j]),
        })

    # --- filter_semantic_duplicates ---
    filter_cases = []
    for _ in range(400):
        n_sel = pyrng.randint(0, 4)
        n_cand = pyrng.randint(0, 12)
        selected = [{"word": f"w{pyrng.randrange(N)}"} for _ in range(n_sel)]
        # 未知語も混ぜる
        candidates = [
            {"word": f"w{pyrng.randrange(N)}" if pyrng.random() < 0.85 else "unknown"}
            for _ in range(n_cand)
        ]
        threshold = pyrng.choice([0.5, 0.7, 0.85, 0.95])
        filter_cases.append({
            "candidates": [c["word"] for c in candidates],
            "selected": [s["word"] for s in selected],
            "threshold": threshold,
            "result": [
                c["word"] for c in em.filter_semantic_duplicates(
                    candidates, selected, threshold)
            ],
        })

    # --- get_diverse_new_words ---
    diverse_cases = []
    for _ in range(400):
        n_cand = pyrng.randint(0, 20)
        candidates = [
            {"word": f"w{pyrng.randrange(N)}" if pyrng.random() < 0.85 else "unknown"}
            for _ in range(n_cand)
        ]
        count = pyrng.randint(0, 8)
        threshold = pyrng.choice([0.5, 0.7, 0.85, 0.95])
        diverse_cases.append({
            "candidates": [c["word"] for c in candidates],
            "count": count,
            "threshold": threshold,
            "result": [
                c["word"] for c in em.get_diverse_new_words(
                    candidates, count, threshold)
            ],
        })

    # --- _weighted_pick の重み ---
    weight_cases = []
    for _ in range(500):
        n = pyrng.randint(1, 8)
        sims = [pyrng.uniform(-1, 1) for _ in range(n)]
        if pyrng.random() < 0.15:  # 全て同点
            sims = [sims[0]] * n
        min_sim, max_sim = min(sims), max(sims)
        if max_sim == min_sim:
            weights = None
        else:
            weights = [(s - min_sim) / (max_sim - min_sim) + 0.1 for s in sims]
        weight_cases.append({"sims": sims, "weights": weights})

    out = os.path.join(os.path.dirname(__file__), "embeddings_golden.json")
    with open(out, "w") as f:
        json.dump({
            "dim": DIM,
            "npy_base64": npy_b64,
            "words": words,
            "cosine_cases": cos_cases,
            "filter_cases": filter_cases,
            "diverse_cases": diverse_cases,
            "weight_cases": weight_cases,
        }, f)
    print(
        f"wrote cos={len(cos_cases)} filter={len(filter_cases)} "
        f"diverse={len(diverse_cases)} weights={len(weight_cases)} -> {out}",
        file=sys.stderr,
    )


main()
