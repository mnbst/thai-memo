#!/usr/bin/env python3
"""語ごとに、例文の時点（TimeFrames）へ自然に置けるかを Jev で判定する。

出力は functions/go/internal/sentence/time_frames.json（go:embed で同梱）。
値の並びは Go の TimeFrames と同じ。TimeFrames を変えたら FRAMES も揃えて流し直す。

    TYPESAFE_API_KEY=... python3 scripts/build_time_frames.py
"""

import concurrent.futures as cf
import json
import os
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
WORDS = ROOT / "scripts" / "corpus" / "freq_rank_top10000.json"
OUT = ROOT / "functions" / "go" / "internal" / "sentence" / "time_frames.json"

# TimeFrames と同じ順。
FRAMES = [
    ("now", "happening right now, at the moment of speaking (in progress or current state)"),
    ("just_now", "something that happened a moment ago, minutes before speaking"),
    ("future", "a plan or intention for later or the future"),
    ("habit", "a habit, routine, or something that happens regularly"),
    ("past", "something that happened yesterday or earlier, or a past experience"),
]

QUESTIONS = {
    key: {
        "type": "noul",
        "instructions": "A learner needs one short, natural everyday Thai sentence that uses the "
        f"Thai word in `word` with its ordinary meaning. Can such a sentence naturally describe {desc}?",
        "criteria": {
            "true": "Yes, the word fits this time frame naturally and without strain.",
            "false": "The word clashes with this time frame (e.g. a word meaning tomorrow in a past "
            "sentence) or the sentence would be forced.",
        },
    }
    for key, desc in FRAMES
}


def judge(word, key):
    body = {"model": "jev-latest", "state": {"word": word}, "questions": QUESTIONS}
    req = urllib.request.Request(
        "https://api.typesafe.ai/v1/systemone",
        data=json.dumps(body).encode(),
        headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"},
    )
    for _ in range(4):
        try:
            answers = json.load(urllib.request.urlopen(req, timeout=60))["answers"]
            return word, [round(answers[k]["noul"], 2) for k, _ in FRAMES]
        except Exception:
            pass
    return word, None


def main():
    key = os.environ["TYPESAFE_API_KEY"]
    words = list(json.loads(WORDS.read_text()))
    with cf.ThreadPoolExecutor(12) as ex:
        results = dict(ex.map(lambda w: judge(w, key), words))
    table = {w: p for w, p in results.items() if p is not None}
    OUT.write_text(json.dumps(table, ensure_ascii=False, separators=(",", ":")) + "\n")
    print(f"{len(table)}/{len(words)} 語 → {OUT}")


if __name__ == "__main__":
    main()
