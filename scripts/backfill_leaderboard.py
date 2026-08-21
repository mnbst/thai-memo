"""Backfill leaderboard/{uid} from users/{uid}.estimated_vocab.

leaderboard doc は updateUvm 実行時にしか作られないため、機能追加前からいる
ユーザーがランキングに載らない。既存の estimated_vocab を一度だけ複製する。

Usage:
  cd functions/python
  .venv/bin/python ../../scripts/backfill_leaderboard.py
  .venv/bin/python ../../scripts/backfill_leaderboard.py --apply
"""

from __future__ import annotations

import argparse
import os
import sys
import time

import firebase_admin
from firebase_admin import firestore

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
FUNCTIONS_PYTHON = os.path.join(ROOT, "functions", "python")
if FUNCTIONS_PYTHON not in sys.path:
    sys.path.insert(0, FUNCTIONS_PYTHON)

from uvm import _assign_nickname  # noqa: E402

PROGRESS_INTERVAL = 50


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", default="thai-memo-prod")
    parser.add_argument(
        "--apply",
        action="store_true",
        help="Write leaderboard docs. Without it, only report what would change.",
    )
    args = parser.parse_args()

    os.environ["GOOGLE_CLOUD_PROJECT"] = args.project
    firebase_admin.initialize_app(options={"projectId": args.project})
    db = firestore.client()

    print(f"Project: {args.project}", flush=True)
    print("mode:", "apply" if args.apply else "dry-run", flush=True)

    checked = 0
    zero = 0
    already = 0
    written = 0
    named = 0
    failed = 0

    for doc in db.collection("users").stream(timeout=120):
        checked += 1
        if checked % PROGRESS_INTERVAL == 0:
            print(f"progress checked={checked} written={written}", flush=True)

        vocab = (doc.to_dict() or {}).get("estimated_vocab", 0)
        vocab = int(vocab) if isinstance(vocab, (int, float)) else 0
        # 0 は順位が付かない（クライアント側も rank なし扱い）ので作らない
        if vocab <= 0:
            zero += 1
            continue

        ref = db.collection("leaderboard").document(doc.id)
        existing = ref.get()
        if existing.exists:
            # 既に updateUvm が書いた doc は最新。上書きしない。
            already += 1
            continue

        if not args.apply:
            written += 1
            continue

        # nickname は uvm と同じ採番（nicknames/{name} を create して一意性担保）
        try:
            nickname = _assign_nickname(db, doc.id)
            payload = {"vocab": vocab, "updated_at": time.time()}
            if nickname:
                payload["nickname"] = nickname
                named += 1
            ref.set(payload, merge=True)
            written += 1
        except Exception as exc:  # 1件の失敗で全体を止めない
            failed += 1
            print(f"failed uid={doc.id}: {exc}", flush=True)

    print(
        f"\nchecked={checked} zero_vocab={zero} already_present={already} "
        f"{'written' if args.apply else 'would_write'}={written} "
        f"nickname_assigned={named} failed={failed}",
        flush=True,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
