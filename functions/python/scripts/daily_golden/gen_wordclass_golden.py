"""word_classes.py の分類を Python 実装から書き出す。

Go 版 internal/wordclass との差分テストに使う。
出力先: functions/python/scripts/daily_golden/wordclass_golden.json
"""

import itertools
import json
import os
import random
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", ".."))

import word_classes as wc  # noqa: E402


def main() -> None:
    all_words = sorted({w for c in wc.CLASSES.values() for w in c["words"]})

    single = [
        {
            "word": w,
            "classify": wc.classify(w),
            "is_function_word": wc.is_function_word(w),
        }
        for w in all_words
    ]
    # 辞書に無い語（内容語）も混ぜる
    for w in ["กิน", "ข้าว", "ไม่มีこんな語", "", "สวัสดี"]:
        single.append({
            "word": w,
            "classify": wc.classify(w),
            "is_function_word": wc.is_function_word(w),
        })

    # classify_all は重複除去と出現順が要点なので、順列を作って確かめる
    rng = random.Random(20260827)
    multi = []
    for _ in range(3000):
        n = rng.randint(0, 5)
        words = [rng.choice(all_words + ["กิน", "ข้าว", "สวัสดี"]) for _ in range(n)]
        multi.append({"words": words, "class_ids": wc.classify_all(words)})
    # 同じクラスの語を並べたケースを明示的に足す
    for cid, c in wc.CLASSES.items():
        if len(c["words"]) >= 2:
            multi.append({
                "words": c["words"][:3],
                "class_ids": wc.classify_all(c["words"][:3]),
            })
    multi.append({"words": [], "class_ids": wc.classify_all([])})
    multi.append({"words": None, "class_ids": wc.classify_all(None)})

    # 複数クラスに重複して現れる語（先に定義したクラスが勝つ）
    counts = {}
    for cid, c in wc.CLASSES.items():
        for w in c["words"]:
            counts.setdefault(w, []).append(cid)
    duplicated = {w: cids for w, cids in counts.items() if len(cids) > 1}

    out = os.path.join(os.path.dirname(__file__), "wordclass_golden.json")
    with open(out, "w") as f:
        json.dump({
            "single": single,
            "multi": multi,
            "duplicated_words": duplicated,
            "classes": {
                cid: {
                    "label": c["label"],
                    "function_word": bool(c.get("function_word")),
                    "rule": c.get("rule") or "",
                    "words": c["words"],
                }
                for cid, c in wc.CLASSES.items()
            },
        }, f, ensure_ascii=False)
    print(
        f"wrote single={len(single)} multi={len(multi)} "
        f"duplicated={len(duplicated)} -> {out}",
        file=sys.stderr,
    )


main()
