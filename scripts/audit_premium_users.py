"""premium ユーザーのサブスク状態を監査する（読み取り専用）

「ストア通知の取りこぼしで premium が永久に残っている」ユーザーを洗い出す。

usage:
  cd functions/python
  uv run python ../../scripts/audit_premium_users.py [prod|tester|dev]
"""

import os
import sys
from datetime import datetime, timezone, timedelta

PROJECTS = {
    'prod': 'thai-memo-prod',
    'tester': 'thai-memo-67139',
    'dev': 'thai-memo-dev',
}
env = sys.argv[1] if len(sys.argv) > 1 else 'prod'
project = PROJECTS[env]
os.environ['GOOGLE_CLOUD_PROJECT'] = project

import firebase_admin
from firebase_admin import firestore

NOW = datetime.now(timezone.utc)
DAY = timedelta(days=1)
GRACE_MAX = timedelta(days=30)
STORE_PLATFORMS = ('ios', 'android')

firebase_admin.initialize_app(options={'projectId': project})
db = firestore.client()

docs = [d for d in db.collection('users').stream()
        if (d.to_dict() or {}).get('tier') == 'premium']
print(f"[{env}] premium users: {len(docs)}\n")

buckets: dict[str, list[str]] = {
    'lapsed_over_24h': [],      # 期限を24h超過（旧ロジックでも降格対象＝バッチ未処理）
    'grace_over_30d': [],       # 猶予期間の上限超過（今回の修正で降格対象）
    'store_no_expiry': [],      # ストア購入なのに expires_at なし（今回の修正で降格対象）
    'no_subscription': [],      # subscription フィールドなし（手動/dev想定・対象外）
    'manual': [],               # 手動付与（対象外）
    'healthy': [],
}

for d in docs:
    data = d.to_dict() or {}
    sub = data.get('subscription') or {}
    if not sub:
        buckets['no_subscription'].append(d.id)
        continue

    platform = sub.get('platform')
    status = sub.get('status')
    expires = sub.get('expires_at')
    expires_dt = expires.astimezone(timezone.utc) if expires else None
    is_store = platform in STORE_PLATFORMS

    if expires_dt is None:
        key = 'store_no_expiry' if is_store else 'manual'
    elif status == 'grace_period':
        key = 'grace_over_30d' if NOW - expires_dt > GRACE_MAX else 'healthy'
    elif NOW - expires_dt > DAY:
        key = 'lapsed_over_24h'
    else:
        key = 'healthy'

    label = (f"{d.id} platform={platform} status={status} "
             f"expires={expires_dt.isoformat() if expires_dt else 'None'} "
             f"auto_renew={sub.get('auto_renewing')}")
    buckets[key].append(label)

for key, items in buckets.items():
    print(f"--- {key}: {len(items)}")
    for item in items:
        print(f"    {item}")
    print()
