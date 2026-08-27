"""uvm.py の単語選定・露出まわりの純粋部分の golden を作る。

対象:
  - scan_band                     ランク帯の算出
  - 候補の切り出し                get_session_words のリスト内包（rank 帯 × 2文字以上）
  - 抽選の重み                    未習語 sqrt 重み / 既習語 1-P 重み
  - _filter_candidates_by_topic   テーマ embedding での絞り込みと帯域外への拡張
  - 露出による P 更新             register_exposure の 1 語ぶんの計算
  - get_sentence_words / get_exposed_words

抽選そのもの（random.choices）は Python と Go で乱数列が違うので比べない。
重みまで一致すれば分布は同じになる。

出力: session_golden.json（Go 側の TestSessionAgainstPythonGolden が読む）
"""

import base64
import io
import json
import math
import os
import random
import sys

import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", ".."))

import embeddings as em  # noqa: E402
import uvm  # noqa: E402

DIM = 32
N = 300

OUT = os.path.join(os.path.dirname(__file__), "session_golden.json")


def scan_band_cases():
    vocabs = [0, 1, 2, 7, 8, 15, 16, 49, 50, 51, 84, 85, 99, 100, 101, 500, 1000, 9999]
    return [{"estimated_vocab": v, "want": list(uvm.scan_band(v))} for v in vocabs]


def band_candidate_cases(freq_rank):
    """get_session_words:406 のリスト内包と同じ条件で候補を切り出す。"""
    cases = []
    for low, high in [(0, 20), (0, 0), (5, 5), (10, 3), (0, 100), (90, 120), (250, 400)]:
        cands = [
            {"word": w, "rank": r}
            for w, r in freq_rank.items()
            if low <= r <= high and len(w) >= 2
        ]
        # rank 順に正規化する（Go は map 反復順が不定なので rank で並べ直す）
        cands.sort(key=lambda c: c["rank"])
        cases.append({"low": low, "high": high, "want": cands})
    return cases


def weight_cases(freq_rank, rng):
    """未習語の sqrt 重みと、既習語の 1-P 重み。"""
    cases = []
    for _ in range(30):
        low = rng.randrange(0, 200)
        high = low + rng.randrange(0, 60)
        cands = sorted(
            (
                {"word": w, "rank": r}
                for w, r in freq_rank.items()
                if low <= r <= high and len(w) >= 2
            ),
            key=lambda c: c["rank"],
        )
        if not cands:
            continue
        max_rank = max(c["rank"] for c in cands)
        zero_weights = [math.sqrt(max_rank - c["rank"] + 1) for c in cands]
        p_map = {
            c["word"]: rng.choice([0.0, 0.05, 0.4, 0.9, 1.0, 1.4])
            for c in cands
            if rng.random() < 0.7
        }
        unknown_weights = [max(0.0, 1.0 - p_map.get(c["word"], 0.0)) for c in cands]
        cases.append(
            {
                "candidates": cands,
                "p_map": p_map,
                "zero_weights": zero_weights,
                "unknown_weights": unknown_weights,
                # zero_p の抽出も固定する（未登録 or P==0）
                "zero_p_words": [
                    c["word"]
                    for c in cands
                    if c["word"] not in p_map or p_map[c["word"]] == 0.0
                ],
            }
        )
    return cases


def filter_cases(freq_rank, words, rng):
    cases = []
    # 帯域が rank 0 から始まると拡張ループが 1 周目で break する。
    # 閾値を誰も超えないテーマ embedding と組み合わせると、拡張で何も
    # 見つからないまま元の候補をそのまま返す経路（関数末尾）を踏む。
    for low, high in [(0, 3), (0, 5), (0, 8)]:
        cands = sorted(
            (
                {"word": w, "rank": r}
                for w, r in freq_rank.items()
                if low <= r <= high and len(w) >= 2
            ),
            key=lambda c: c["rank"],
        )
        # 候補の誰とも似ないベクトルを棄却サンプリングで作る
        topic_emb = None
        for _ in range(20000):
            v = np.array([rng.gauss(0, 1) for _ in range(DIM)], dtype=np.float32)
            v /= np.linalg.norm(v)
            sims = [
                em.cosine_similarity(em.get_embedding(c["word"]), v) for c in cands
            ]
            if sims and max(sims) < uvm.TOPIC_FILTER_THRESHOLD:
                topic_emb = v
                break
        if topic_emb is None:
            raise RuntimeError(f"閾値未満のテーマ embedding を作れない: {low}-{high}")
        got = uvm._filter_candidates_by_topic(
            [dict(c) for c in cands], topic_emb, freq_rank, low
        )
        cases.append(
            {
                "low": low,
                "high": high,
                "topic_emb": [float(x) for x in topic_emb],
                "want": [c["word"] for c in got],
            }
        )

    for _ in range(24):
        low = rng.randrange(0, 250)
        high = low + rng.randrange(0, 40)
        cands = sorted(
            (
                {"word": w, "rank": r}
                for w, r in freq_rank.items()
                if low <= r <= high and len(w) >= 2
            ),
            key=lambda c: c["rank"],
        )
        # テーマ embedding は候補の1本を少しずらしたもの。閾値を跨ぐ候補が
        # 出るように、無相関なベクトルも混ぜる。
        idx = rng.randrange(0, N)
        if rng.random() < 0.5:
            topic_emb = em._embeddings[idx].copy()
        else:
            v = np.array(
                [rng.gauss(0, 1) for _ in range(DIM)], dtype=np.float32
            )
            topic_emb = v / np.linalg.norm(v)
        got = uvm._filter_candidates_by_topic(
            [dict(c) for c in cands], topic_emb, freq_rank, low
        )
        cases.append(
            {
                "low": low,
                "high": high,
                "topic_emb": [float(x) for x in topic_emb],
                "want": [c["word"] for c in got],
            }
        )
    return cases


def exposure_cases():
    cases = []
    for old_p in [None, 0.0, 0.1, 0.4, 0.9, 0.98, 0.99, 1.0]:
        for count in [1, 2, 3, 7]:
            p = uvm.NEW_WORD_P if old_p is None else old_p
            new_p = p
            for _ in range(count):
                new_p = new_p + uvm.ALPHA_EXPOSURE * (1 - new_p)
            cases.append(
                {
                    "old_p": p,
                    "count": count,
                    "want": max(uvm.P_MIN, min(uvm.P_MAX, new_p)),
                }
            )
    return cases


def word_cases():
    breakdowns = [
        [],
        [{"word": "กิน"}, {"word": "ข้าว"}, {"word": "กิน"}],
        [{"word": " กิน "}, {"word": ""}, {"word": "   "}, {"word": "ข้าว"}],
        [{"word": "กิน"}, "not-a-dict", {"word": "ข้าว"}, {}],
        [{"word": "ๆ"}, {"word": "กินๆ"}, {"word": "กิน"}],
    ]
    targets = [None, [], ["กิน"], ["กิน", "ข้าว"], ["ไม่มี"]]
    cases = []
    for wb in breakdowns:
        sentence = {"word_breakdown": wb}
        all_words = uvm.get_sentence_words(sentence)
        for t in targets:
            cases.append(
                {
                    # Go 側は word_breakdown を文字列リストにしてから渡すので、
                    # dict でない要素・word 欠落は Python 側で落としたものを渡す。
                    "words": [
                        str(w.get("word", "")) if isinstance(w, dict) else ""
                        for w in wb
                    ],
                    "target_words": t,
                    "want_all": all_words,
                    "want_exposed": uvm.get_exposed_words(sentence, t),
                }
            )
    return cases


def main() -> None:
    rng = np.random.default_rng(20260827)
    matrix = rng.standard_normal((N, DIM)).astype(np.float32)
    matrix /= np.linalg.norm(matrix, axis=1, keepdims=True)
    words = [{"word": f"ก{i:03d}", "rank": i + 1} for i in range(N)]
    # 1文字語も混ぜる（len(word) >= 2 のフィルタを踏ませる）
    for i in range(0, N, 17):
        words[i]["word"] = chr(0x0E01 + (i % 40))

    em._embeddings = matrix
    em._words = words
    em._word_to_idx = {w["word"]: i for i, w in enumerate(words)}
    # get_embedding は _word_to_idx 経由。テーマ embedding は使わせない。
    em._topic_embeddings = {}

    freq_rank = {w["word"]: w["rank"] for w in words}

    buf = io.BytesIO()
    np.save(buf, matrix, allow_pickle=False)

    pyrng = random.Random(20260827)
    out = {
        "npy_base64": base64.b64encode(buf.getvalue()).decode(),
        "words": words,
        "freq_rank": freq_rank,
        "scan_band": scan_band_cases(),
        "band_candidates": band_candidate_cases(freq_rank),
        "weights": weight_cases(freq_rank, pyrng),
        "filter_by_topic": filter_cases(freq_rank, words, pyrng),
        "exposure_p": exposure_cases(),
        "sentence_words": word_cases(),
    }
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False)
    print(f"wrote {OUT}")
    for k, v in out.items():
        if isinstance(v, list):
            print(f"  {k}: {len(v)}")


if __name__ == "__main__":
    main()
