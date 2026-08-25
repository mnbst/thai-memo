"""prod の例文生成クォータ到達率を集計する。

「1日の上限が足りているか / 余っているか」を測る。上限を上下させる判断の材料。

data source:
  Cloud Logging (generatethaisentence) の textPayload。
  sentence_handlers.py が userId 入りで以下を print している。
    - "Request completed successfully: {... 'userId': ...}"  成功
    - "Quota exceeded: {... 'userId': ...}"                   上限到達
  tier はログに無いので Firestore users から引く（現在値での近似）。

  ログ保持は既定30日。それより前は取れない。

usage:
  cd functions/python
  .venv/bin/python3 ../../scripts/prod_quota_reach.py [--days 30]
"""

import argparse
import json
import os
import re
import subprocess
import sys
from collections import Counter, defaultdict
from datetime import datetime, timedelta, timezone

JST = timezone(timedelta(hours=9))
PROJECT = "thai-memo-prod"
SERVICE = "generatethaisentence"

# log_data は Python の dict repr で出るので JSON では読めない。userId だけ抜く。
USER_ID_RE = re.compile(r"'userId': '([^']+)'")


def fetch_logs(days: int, limit: int) -> list[dict]:
    since = (datetime.now(timezone.utc) - timedelta(days=days)).strftime(
        "%Y-%m-%dT%H:%M:%SZ"
    )
    log_filter = (
        f'resource.type="cloud_run_revision" '
        f'AND resource.labels.service_name="{SERVICE}" '
        f'AND timestamp>="{since}" '
        f'AND (textPayload:"Request completed successfully" '
        f'OR textPayload:"Quota exceeded")'
    )
    result = subprocess.run(
        [
            "gcloud", "logging", "read", log_filter,
            f"--project={PROJECT}",
            f"--limit={limit}",
            "--format=json",
        ],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        print(result.stderr[:2000], file=sys.stderr)
        sys.exit(1)
    return json.loads(result.stdout or "[]")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--days", type=int, default=30)
    parser.add_argument("--limit", type=int, default=20000)
    args = parser.parse_args()

    print(f"Fetching logs (last {args.days}d)...", flush=True)
    entries = fetch_logs(args.days, args.limit)
    print(f"  log entries: {len(entries)}")

    # (uid, JST日付) ごとの成功回数と上限到達回数
    success: Counter = Counter()
    exceeded: Counter = Counter()

    for e in entries:
        text = e.get("textPayload") or ""
        m = USER_ID_RE.search(text)
        if not m:
            continue
        uid = m.group(1)
        if uid == "anonymous":
            continue
        ts = e.get("timestamp")
        if not ts:
            continue
        day = datetime.fromisoformat(ts.replace("Z", "+00:00")).astimezone(JST).date()
        key = (uid, day)
        if text.startswith("Quota exceeded"):
            exceeded[key] += 1
        elif text.startswith("Request completed successfully"):
            success[key] += 1

    if not success:
        print("成功ログが0件。ログ保持期間外か、フィルタが合っていない。")
        return

    # tier を Firestore から引く（ログには無い）
    os.environ["GOOGLE_CLOUD_PROJECT"] = PROJECT
    import firebase_admin
    from firebase_admin import firestore

    firebase_admin.initialize_app(options={"projectId": PROJECT})
    db = firestore.client()
    tier_of: dict[str, str] = {}
    for doc in db.collection("users").stream():
        tier_of[doc.id] = (doc.to_dict() or {}).get("tier", "free")

    active_days = set(success)
    capped_days = {k for k in exceeded if k in active_days}

    print("\n=== 上限到達率（アクティブ人日ベース） ===")
    print(f"  アクティブ人日: {len(active_days)}")
    print(f"  上限に到達    : {len(capped_days)} ({len(capped_days) / len(active_days) * 100:.1f}%)")

    print("\n=== tier 別 ===")
    by_tier: dict[str, list] = defaultdict(list)
    for key in active_days:
        by_tier[tier_of.get(key[0], "free")].append(key)
    for tier in sorted(by_tier):
        days = by_tier[tier]
        hit = [k for k in days if k in capped_days]
        counts = sorted(success[k] for k in days)
        users = len({k[0] for k in days})
        print(
            f"  {tier:8s}: 人日={len(days):5d} ユーザー={users:4d} "
            f"到達={len(hit):4d} ({len(hit) / len(days) * 100:5.1f}%) "
            f"生成数/人日 中央値={counts[len(counts) // 2]:3d} 平均={sum(counts) / len(counts):5.1f}"
        )

    print("\n=== 1人日あたりの生成数分布 ===")
    for tier in sorted(by_tier):
        counts = Counter(success[k] for k in by_tier[tier])
        total = sum(counts.values())
        print(f"  [{tier}]")
        for n in sorted(counts):
            bar = "#" * max(1, round(counts[n] / total * 40))
            print(f"    {n:3d}文: {counts[n]:4d} ({counts[n] / total * 100:5.1f}%) {bar}")

    print("\n=== 上限に到達したユーザー ===")
    per_user = Counter(uid for uid, _ in capped_days)
    if not per_user:
        print("  なし（誰も上限に当たっていない）")
    else:
        for uid, n in per_user.most_common(20):
            user_days = len([k for k in active_days if k[0] == uid])
            print(f"  {uid[:12]}… tier={tier_of.get(uid, '?'):8s} 到達 {n}日 / アクティブ {user_days}日")


if __name__ == "__main__":
    main()
