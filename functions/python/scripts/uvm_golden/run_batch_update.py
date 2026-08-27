"""dev Firestore に対して Python 版 batch_update_uvm を1回だけ流す。

Go 版との差分テスト（functions/go/update_uvm_live_test.go）から呼ばれる。
種まきと比較は Go 側が行い、ここは Python 実装を走らせるだけ。

  echo '{"uid":..,"results":[..],"quiz_type":"","is_premium":false}' \
    | uv run python scripts/uvm_golden/run_batch_update.py
"""

import json
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", ".."))

import firebase_admin  # noqa: E402
from firebase_admin import firestore  # noqa: E402

from sentence_service import get_freq_rank  # noqa: E402
from uvm import batch_update_uvm  # noqa: E402


def main():
    req = json.load(sys.stdin)
    firebase_admin.initialize_app()
    db = firestore.client()
    batch_update_uvm(
        db,
        req["uid"],
        req["results"],
        freq_rank=get_freq_rank(),
        quiz_type=req.get("quiz_type", ""),
        is_premium=req.get("is_premium", True),
    )
    print("python: done", file=sys.stderr)


if __name__ == "__main__":
    main()
