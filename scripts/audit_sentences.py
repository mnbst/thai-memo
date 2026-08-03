"""昨日〜今日に生成された例文を全環境から取得する。

usage:
  cd functions/python && uv run python <this> [days]
"""

import json
import sys
from datetime import datetime, timedelta, timezone

import firebase_admin
from firebase_admin import firestore

JST = timezone(timedelta(hours=9))
DAYS = int(sys.argv[1]) if len(sys.argv) > 1 else 1
cutoff = (datetime.now(JST) - timedelta(days=DAYS)).replace(
    hour=0, minute=0, second=0, microsecond=0
)

PROJECTS = {
    "prod": "thai-memo-prod",
    "tester": "thai-memo-67139",
    "dev": "thai-memo-dev",
}

out = []
for env, pid in PROJECTS.items():
    app = firebase_admin.initialize_app(options={"projectId": pid}, name=env)
    db = firestore.client(app)
    try:
        docs = list(
            db.collection_group("sentences")
            .where("created_at", ">=", cutoff)
            .stream()
        )
        mode = "cg"
    except Exception as exc:
        print(f"[{env}] collection_group failed ({exc}); fallback", file=sys.stderr)
        docs = []
        for u in db.collection("users").stream():
            for d in (
                db.collection("users")
                .document(u.id)
                .collection("sentences")
                .where("created_at", ">=", cutoff)
                .stream()
            ):
                docs.append(d)
        mode = "scan"
    print(f"[{env}] {len(docs)} sentences ({mode})", file=sys.stderr)
    for d in docs:
        s = d.to_dict()
        ca = s.get("created_at")
        out.append(
            {
                "env": env,
                "uid": d.reference.parent.parent.id,
                "created_at": ca.astimezone(JST).isoformat() if ca else None,
                "tier": s.get("generation_tier"),
                "thai": s.get("thai_text"),
                "pron": s.get("pronunciation"),
                "ja": s.get("japanese_translation"),
                "key_word": s.get("key_word"),
                "context": s.get("context"),
                "words": [
                    (w.get("thai"), w.get("meaning"))
                    for w in (s.get("word_breakdown") or [])
                ],
            }
        )

out.sort(key=lambda x: (x["env"], x["created_at"] or ""))
print(json.dumps(out, ensure_ascii=False, indent=1))
