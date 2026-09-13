"""過去に月額を購入して失効した prod ユーザーへ無償移行の名簿フラグを立てる。

名簿（users.lifetime_migration_eligible）は migrateToLifetime のゲート。
リリース時点の購入者だけを対象にするため、後から買った人が入らないよう
このスクリプトは手動で回す。--apply 無しは対象の表示のみ。

usage:
  cd tools
  uv run python ../scripts/set_lifetime_migration_eligible.py [--apply]
"""
import sys
from google.cloud import firestore

apply = '--apply' in sys.argv
db = firestore.Client(project='thai-memo-prod')

targets = []
for doc in db.collection('users').stream():
    d = doc.to_dict() or {}
    sub = d.get('subscription') or {}
    if not isinstance(sub, dict):
        continue
    if sub.get('platform') not in ('ios', 'android'):
        continue
    if sub.get('lifetime') is True:
        continue
    if sub.get('status') != 'expired':
        continue
    if d.get('lifetime_migration_eligible') is True:
        continue
    targets.append(doc.id)

print(f"対象 {len(targets)} 件: {targets}")
if apply:
    for uid in targets:
        db.collection('users').document(uid).update(
            {'lifetime_migration_eligible': True})
        print(f"set {uid}")
