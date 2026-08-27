"""sentence_service.py / word_gap.py の純粋ロジックを Python 実装から書き出す。

Go 版 internal/sentence, internal/wordgap との差分テストに使う。
出力先: functions/python/scripts/daily_golden/service_golden.json
"""

import json
import os
import random
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", ".."))

import sentence_service as ss  # noqa: E402
import word_gap as wg  # noqa: E402

THAI = ["ฉัน", "กิน", "ข้าว", "ไป", "ตลาด", "แมว", "สวย", "จริง", "นะ", "ครับ"]
SPACES = ["", " ", "  ", "　", " ", "\t", "\n"]


def main() -> None:
    rng = random.Random(20260827)

    # --- _compact_yamok / _strip_spaces / _match_word ---
    text_cases = []
    for _ in range(2000):
        parts = []
        for _ in range(rng.randint(1, 6)):
            parts.append(rng.choice(THAI))
            if rng.random() < 0.4:
                parts.append(rng.choice(SPACES))
            if rng.random() < 0.25:
                parts.append(rng.choice(SPACES) + "ๆ")
        text = "".join(parts)
        text_cases.append({
            "text": text,
            "compact_yamok": ss._compact_yamok(text),
            "strip_spaces": ss._strip_spaces(text),
        })

    match_cases = []
    for _ in range(1500):
        a = rng.choice(THAI) + rng.choice(["", "ๆ", " ๆ", "　ๆ"])
        b = rng.choice(THAI) + rng.choice(["", "ๆ", " ๆ"])
        a = rng.choice(SPACES) + a + rng.choice(SPACES)
        match_cases.append({"a": a, "b": b, "result": ss._match_word(a, b)})

    # --- validate_target_words ---
    validate_cases = []
    for _ in range(800):
        wb = [{"word": rng.choice(THAI) + rng.choice(["", "ๆ"])}
              for _ in range(rng.randint(0, 6))]
        if rng.random() < 0.2:
            wb.append({"no_word": 1})  # dict だが word 無し
        if rng.random() < 0.1:
            wb.append("not a dict")
        targets = [rng.choice(THAI) + rng.choice(["", "ๆ"])
                   for _ in range(rng.randint(0, 3))]
        if rng.random() < 0.15:
            targets.append("  ")
        sentence = {"word_breakdown": wb}
        validate_cases.append({
            "breakdown_words": [
                str(w.get("word", "")) for w in wb if isinstance(w, dict)
            ],
            "target_words": targets,
            "missing": ss.validate_target_words(sentence, targets),
        })

    # --- _normalize_thai_spacing ---
    spacing_cases = []
    for _ in range(1200):
        n = rng.randint(1, 9)
        words = [rng.choice(THAI) for _ in range(n)]
        mode = rng.random()
        if mode < 0.3:
            text = " ".join(words)            # 全語のあいだに空白（崩壊）
        elif mode < 0.45:
            text = "".join(words)             # 空白なし
        elif mode < 0.6:
            half = max(1, n // 2)
            text = "".join(words[:half]) + " " + "".join(words[half:])  # 2節
        elif mode < 0.85:
            # トークン数 / 語数 が 0.5〜0.7 の帯に入るよう、語をまとめて割る。
            # ここを作らないと 0.7 という閾値そのものを検証できない
            # （2節=2トークンでは 0.5 未満、全分割では 1.0 になり素通りする）。
            k = rng.randint(2, max(2, n - 1)) if n >= 3 else 2
            bounds = sorted(rng.sample(range(1, n), min(k - 1, n - 1))) if n > 1 else []
            chunks, prev = [], 0
            for b in bounds:
                chunks.append("".join(words[prev:b]))
                prev = b
            chunks.append("".join(words[prev:]))
            text = " ".join(c for c in chunks if c)
        else:
            text = " ".join(words[:-1]) + rng.choice([" ", ""]) + words[-1]
        if rng.random() < 0.2:
            text = text.replace("จริง", "จริง ๆ")
        sentence = {
            "thai_text": text,
            "word_breakdown": [{"word": w} for w in words],
        }
        before = dict(sentence)
        ss._normalize_thai_spacing(sentence)
        spacing_cases.append({
            "thai_text": before["thai_text"],
            "breakdown_words": words,
            "result_text": sentence["thai_text"],
            "result_words": [w["word"] for w in sentence["word_breakdown"]],
        })

    # --- retry prompt ---
    retry_cases = []
    for _ in range(50):
        prompt = "ベースプロンプト " + str(rng.randrange(1000))
        missing = [rng.choice(THAI) for _ in range(rng.randint(1, 3))]
        thai = "".join(rng.choice(THAI) for _ in range(3))
        retry_cases.append({
            "prompt": prompt,
            "missing": missing,
            "thai_text": thai,
            "retry": ss._build_retry_prompt(prompt, missing),
            "mismatch": ss._build_mismatch_retry_prompt(prompt, thai),
        })

    # --- word_gap ---
    gap_cases = []
    for _ in range(1500):
        n = rng.randint(1, 6)
        words = [rng.choice(THAI) for _ in range(n)]
        thai = "".join(words)
        wb = [{"word": w, "meaning": "m"} for w in words]
        mode = rng.random()
        if mode < 0.35 and len(wb) > 1:
            wb.pop(rng.randrange(len(wb)))          # 語を落とす → gap
        elif mode < 0.5 and wb:
            wb[rng.randrange(len(wb))]["word"] = "ไม่มีคำนี้"  # 綴り不一致 → -1
        elif mode < 0.6:
            thai = thai + rng.choice(THAI)           # 末尾に余り
        sentence = {"thai_text": thai, "word_breakdown": wb}
        gaps = wg.find_gaps(sentence)
        gap_cases.append({
            "thai_text": thai,
            "breakdown": [{"word": w.get("word", ""), "meaning": w.get("meaning", "")}
                          for w in wb],
            "gaps": [[i, s] for i, s in gaps],
            "prompt": wg.build_gap_prompt(thai, gaps) if gaps else "",
        })

    # --- apply_gap_words ---
    apply_cases = []
    for _ in range(1500):
        n = rng.randint(2, 7)
        words = [rng.choice(THAI) for _ in range(n)]
        thai = "".join(words)
        # 連続する 1〜3 語を落とす。2語以上落とすと欠落文字列が複数語ぶんになり、
        # 補完側の取り出し順（Python は末尾から）が結果に効く。
        span = rng.randint(1, min(3, len(words) - 1))
        drop = rng.randrange(len(words) - span + 1)
        dropped = words[drop:drop + span]
        wb = [{"word": w, "meaning": "m"}
              for i, w in enumerate(words) if not (drop <= i < drop + span)]
        sentence = {"thai_text": thai, "word_breakdown": list(wb)}
        gaps = wg.find_gaps(sentence)
        if not gaps or gaps[0][0] < 0:
            continue
        # 正しい補完 / 誤った補完 を混ぜる
        if rng.random() < 0.7:
            filled = [{"word": w, "meaning": f"補完{i}"}
                      for i, w in enumerate(dropped)]
        else:
            filled = [{"word": rng.choice(THAI), "meaning": "誤"}
                      for _ in range(span)]
        work = {"thai_text": thai, "word_breakdown": list(wb)}
        ok = wg.apply_gap_words(work, gaps, filled)
        apply_cases.append({
            "thai_text": thai,
            "breakdown": [{"word": w["word"], "meaning": w["meaning"]} for w in wb],
            "gaps": [[i, s] for i, s in gaps],
            "filled": [{"word": f["word"], "meaning": f["meaning"]} for f in filled],
            "ok": ok,
            "result": [{"word": w["word"], "meaning": w.get("meaning", "")}
                       for w in work["word_breakdown"]] if ok else None,
        })

    out = os.path.join(os.path.dirname(__file__), "service_golden.json")
    with open(out, "w") as f:
        json.dump({
            "text_cases": text_cases,
            "match_cases": match_cases,
            "validate_cases": validate_cases,
            "spacing_cases": spacing_cases,
            "retry_cases": retry_cases,
            "gap_cases": gap_cases,
            "apply_cases": apply_cases,
        }, f, ensure_ascii=False)
    print(
        f"wrote text={len(text_cases)} match={len(match_cases)} "
        f"validate={len(validate_cases)} spacing={len(spacing_cases)} "
        f"retry={len(retry_cases)} gap={len(gap_cases)} apply={len(apply_cases)} -> {out}",
        file=sys.stderr,
    )


main()
