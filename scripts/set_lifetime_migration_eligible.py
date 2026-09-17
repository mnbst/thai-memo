"""月額の購入記録を持つ prod ユーザーへ無償移行の名簿フラグを立てる。

名簿（users.lifetime_migration_eligible）は migrateToLifetime のゲート。
実行時点で subscription を持つ人をスナップショットとして名簿に載せる。
status は見ないため、現在課金中（active / canceled / grace_period）と
過去に失効した人（expired）の両方が対象になる。実行後に買った人が自動で
入ることはない。このキャンペーン開始前に一度だけ --apply し、開始後は
再実行しない。--apply 無しは対象の表示のみ。

usage:
  cd tools
  uv run python ../scripts/set_lifetime_migration_eligible.py [--apply]
"""
from __future__ import annotations

import sys
from collections import Counter
from typing import Any

from google.cloud import firestore


def migration_candidate(data: dict[str, Any]) -> tuple[bool, str]:
    """無償移行できる月額購入記録かと、対象外理由を返す。"""
    sub = data.get('subscription') or {}
    if not isinstance(sub, dict):
        return False, 'subscription_invalid'

    platform = sub.get('platform')
    if platform not in ('ios', 'android'):
        return False, 'not_store_purchase'
    if sub.get('lifetime') is True:
        return False, 'already_lifetime'

    # migrateToLifetime が移行元の取引IDを必須にしている。ここを通らない
    # レコードへ名簿フラグを立てると、案内だけ出て移行は必ず失敗する。
    source_id = (
        sub.get('original_transaction_id')
        if platform == 'ios'
        else sub.get('purchase_token')
    )
    if not isinstance(source_id, str) or not source_id:
        return False, 'missing_source_id'

    if data.get('lifetime_migration_eligible') is True:
        return False, 'already_eligible'
    return True, str(sub.get('status') or 'status_missing')


def main(argv: list[str]) -> None:
    apply = '--apply' in argv
    db = firestore.Client(project='thai-memo-prod')

    targets: list[str] = []
    target_statuses: Counter[str] = Counter()
    skipped: Counter[str] = Counter()
    for doc in db.collection('users').stream():
        data = doc.to_dict() or {}
        eligible, detail = migration_candidate(data)
        if eligible:
            targets.append(doc.id)
            target_statuses[detail] += 1
        else:
            skipped[detail] += 1

    print(f"対象 {len(targets)} 件: {targets}")
    print(f"対象status内訳: {dict(sorted(target_statuses.items()))}")
    print(f"対象外理由: {dict(sorted(skipped.items()))}")
    if apply:
        for uid in targets:
            db.collection('users').document(uid).update(
                {'lifetime_migration_eligible': True})
            print(f"set {uid}")


if __name__ == '__main__':
    main(sys.argv[1:])
