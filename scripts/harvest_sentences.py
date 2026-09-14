"""Firestore の既存例文を収集してコーパス素材にする。

users/{uid}/sentences は 30 日で消える（dailyBatch の cleanOldSentences）ので、
生成を始める前に吸い出しておく。sentence_flags で不合格になったものは除外する。

usage:
  uv run --with firebase-admin python scripts/harvest_sentences.py [env ...]
  # 既定は prod tester dev の全環境
出力:
  scripts/bank_out/harvest_{ja,en}.json   例文本体（thai_text で重複排除）
  scripts/bank_out/harvest_report.json    収集統計
"""

import json
import os
import re
import sys
from collections import Counter, defaultdict

import firebase_admin
from firebase_admin import firestore

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "scripts", "bank_out")
RANK_PATH = os.path.join(ROOT, "scripts", "corpus", "freq_rank_top10000.json")

PROJECTS = {
    "prod": "thai-memo-prod",
    "tester": "thai-memo-67139",
    "dev": "thai-memo-dev",
}
envs = sys.argv[1:] or list(PROJECTS)

JP = re.compile(r"[぀-ヿ一-鿿]")
FIELDS = (
    "thai_text", "pronunciation", "japanese_translation",
    "word_breakdown", "context", "key_word",
    "key_word_pronunciation", "key_word_meaning", "generation_tier",
)

with open(RANK_PATH, encoding="utf-8") as f:
    raw_rank = json.load(f)
freq_rank = (
    {e["word"]: e["rank"] for e in raw_rank}
    if isinstance(raw_rank, list) else raw_rank
)

by_text: dict[str, dict] = {}
flagged_texts: set[str] = set()
stats: dict[str, Counter] = defaultdict(Counter)


def keep(d: dict, env: str) -> None:
    text = d.get("thai_text")
    tr = d.get("japanese_translation")
    if not text or not tr or not d.get("word_breakdown"):
        stats[env]["skip_incomplete"] += 1
        return
    if text in by_text:
        stats[env]["dup"] += 1
        return
    item = {k: d.get(k) for k in FIELDS}
    item["lang"] = "ja" if JP.search(tr) else "en"
    item["key_word_rank"] = freq_rank.get(d.get("key_word", ""), 0)
    item["source_env"] = env
    by_text[text] = item
    stats[env]["kept"] += 1


for env in envs:
    app = firebase_admin.initialize_app(
        options={"projectId": PROJECTS[env]}, name=env)
    db = firestore.client(app)

    # 先に不合格例文を集める。判定は thai_text 単位で使い回せる。
    for doc in db.collection("sentence_flags").stream():
        d = doc.to_dict() or {}
        if d.get("thai_text"):
            flagged_texts.add(d["thai_text"])
            stats[env]["flags"] += 1

    try:
        it = db.collection_group("sentences").stream()
        for doc in it:
            stats[env]["scanned"] += 1
            keep(doc.to_dict() or {}, env)
    except Exception as exc:  # collection_group が使えない環境へのフォールバック
        print(f"[{env}] collection_group failed ({exc}); per-user scan",
              file=sys.stderr)
        for u in db.collection("users").stream():
            for doc in u.reference.collection("sentences").stream():
                stats[env]["scanned"] += 1
                keep(doc.to_dict() or {}, env)

# 不合格は全環境ぶんを集め終えてから落とす（環境をまたいで同じ文が出るため）
dropped = [t for t in by_text if t in flagged_texts]
for t in dropped:
    del by_text[t]

os.makedirs(OUT, exist_ok=True)
report = {
    "envs": envs,
    "per_env": {e: dict(c) for e, c in stats.items()},
    "flagged_total": len(flagged_texts),
    "dropped_by_flag": len(dropped),
    "unique_total": len(by_text),
}
for lg in ("ja", "en"):
    items = [v for v in by_text.values() if v["lang"] == lg]
    items.sort(key=lambda v: (v["key_word_rank"] or 10**9, v["thai_text"]))
    with open(os.path.join(OUT, f"harvest_{lg}.json"), "w", encoding="utf-8") as f:
        json.dump(items, f, ensure_ascii=False, indent=1)
    ranks = [v["key_word_rank"] for v in items]
    report[lg] = {
        "count": len(items),
        "rank_unknown": sum(1 for r in ranks if not r),
        "rank_le_5000": sum(1 for r in ranks if 0 < r <= 5000),
        "distinct_key_words": len({v["key_word"] for v in items}),
    }

with open(os.path.join(OUT, "harvest_report.json"), "w", encoding="utf-8") as f:
    json.dump(report, f, ensure_ascii=False, indent=1)
print(json.dumps(report, ensure_ascii=False, indent=1))
