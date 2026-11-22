#!/usr/bin/env python3
"""語ごとに、時点（TimeFrames）の種類（未来なら 予定・意志・見通し・願望 等）へ自然に置けるかを
Gemini Decisions で判定する。

対象は time_frames.json でその時点が候補（0.5 以上）の語だけ。結果は JSONL に1行ずつ追記し
（{"word", "p": {種類: 確率}}）、再実行時は語ごとにまだ無い種類だけを聞く（種類を足したら
流し直せば足りない分だけ判定する）。--gen で Go が埋め込む time_kinds.json を作る。
時点と種類の並びは Go の TimeFrames・TimeKinds と同じ。

usage: GEMINI_API_KEY=... python3 scripts/build_time_kinds.py scripts/corpus/time_kinds.jsonl
       python3 scripts/build_time_kinds.py --gen scripts/corpus/time_kinds.jsonl functions/go/internal/sentence/time_kinds.json
"""
import json, os, subprocess, sys, threading, time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TABLE = ROOT / "functions" / "go" / "internal" / "sentence" / "time_frames.json"
ENDPOINT = "https://generativelanguage.googleapis.com/v1beta/decisions"

# 時点の位置（time_frames.json・Go の TimeFrames）→ 種類。種類の名前は時点をまたいで重ねない。
# 並びは Go の TimeKinds と同じ。
FRAMES = {
    0: [  # 今まさに起きていること
        ("in_progress", "an action that someone is in the middle of doing right now"),
        ("state", "a current state, feeling, or situation at the moment of speaking"),
    ],
    2: [  # これからの予定
        ("plan", "a plan or arrangement fixed for a later time, such as tomorrow, tonight, "
                 "next week, or an appointment"),
        ("intention", "the speaker's own decision or resolve about what they will or will not do "
                      "from now on"),
        ("outlook", "a prediction or expectation of how something will probably turn out later"),
        ("wish", "a hope or wish about what the speaker wants to happen later"),
    ],
    3: [  # いつもの習慣
        ("routine", "a fixed habit or routine that happens regularly"),
        ("recent", "something that has been happening repeatedly or continuously lately, in "
                   "recent days or weeks"),
    ],
    4: [  # 昨日や以前の出来事
        ("event", "a specific event on a particular past day, such as yesterday or last week"),
        ("experience", "a past experience of having done or seen something at some point"),
        ("former", "how things used to be long ago, such as in childhood or in the old days"),
    ],
}
QUESTIONS = {
    k: {"type": "noul", "instructions":
        "The input is one Thai word (`word`). A learner needs one short, natural everyday Thai "
        "sentence that uses this word with its ordinary meaning. Can such a sentence naturally "
        f"describe {desc}? Answer no if the word clashes with this kind of statement or the "
        "sentence would be forced."}
    for kinds in FRAMES.values() for k, desc in kinds
}
lock = threading.Lock()


def ask(key, word, kinds, f):
    body = json.dumps({"model": "gemini-decision-1",
        "input": [{"type": "text", "text": json.dumps({"word": word}, ensure_ascii=False)}],
        "questions": {k: QUESTIONS[k] for k in kinds}}).encode()
    for a in range(6):
        try:
            r = subprocess.run(["curl", "-sS", "--fail-with-body", "-m", "60", ENDPOINT,
                "-H", "x-goog-api-key: " + key, "-H", "Content-Type: application/json",
                "--data-binary", "@-"], input=body, capture_output=True, check=True)
            ans = json.loads(r.stdout)["answers"]
            row = {"word": word, "p": {k: round(ans[k]["noul"], 3) for k in kinds}}
            with lock:
                f.write(json.dumps(row, ensure_ascii=False) + "\n"); f.flush()
            return True
        except Exception as e:  # noqa: BLE001
            if a == 5:
                print("fail", word, e, file=sys.stderr); return False
            time.sleep(2 ** a)


def load(src):
    """語 → {種類: 確率}。"""
    got = {}
    if not os.path.exists(src):
        return got
    for l in open(src):
        if l.strip():
            r = json.loads(l)
            got.setdefault(r["word"], {}).update(r["p"])
    return got


def gen(src, dst):
    """語 → {時点の位置: 種類の確率（TimeKinds の並び）}。種類がそろった時点だけを書く。"""
    table = {}
    for w, p in load(src).items():
        row = {}
        for fi, kinds in FRAMES.items():
            if all(k in p for k, _ in kinds):
                row[str(fi)] = [round(p[k], 2) for k, _ in kinds]
        if row:
            table[w] = row
    Path(dst).write_text(json.dumps(table, ensure_ascii=False, separators=(",", ":")) + "\n")
    print(f"{len(table)} 語 → {dst}")


if sys.argv[1] == "--gen":
    gen(sys.argv[2], sys.argv[3])
    sys.exit(0)

key = os.environ["GEMINI_API_KEY"]
table = json.loads(TABLE.read_text())
got = load(sys.argv[1])
todo = []
for w, probs in table.items():
    missing = [k for fi, kinds in FRAMES.items() if probs[fi] >= 0.5
               for k, _ in kinds if k not in got.get(w, {})]
    if missing:
        todo.append((w, missing))
print(f"todo {len(todo)} / {len(table)}", file=sys.stderr, flush=True)
with open(sys.argv[1], "a") as f, ThreadPoolExecutor(16) as ex:
    ok = sum(ex.map(lambda t: ask(key, t[0], t[1], f), todo))
print(f"ok {ok} / {len(todo)}", file=sys.stderr)
