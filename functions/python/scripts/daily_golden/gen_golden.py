"""daily_sentence.py の判定を Python 実装から書き出す。

Go 版 internal/dailysentence との差分テスト
（functions/go/internal/dailysentence/golden_test.go）に使う。
出力先: functions/python/scripts/daily_golden/golden.json
"""

import json
import os
import random
import sys
from datetime import datetime, timedelta, timezone

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", ".."))

from daily_sentence import (  # noqa: E402
    TIER_STOPPED,
    delivery_skip_reason,
    evaluate_response,
    has_generation_history,
    is_due,
    local_date,
    local_hour,
    uses_premium_trial,
)

MS = 1000
NOW = datetime(2026, 8, 27, 1, 0, 0, tzinfo=timezone.utc)

TIMEZONES = [
    None, "", "Asia/Tokyo", "Asia/Bangkok", "Asia/Kolkata", "Asia/Kathmandu",
    "America/Los_Angeles", "America/New_York", "Europe/Berlin", "Europe/London",
    "Pacific/Chatham", "Pacific/Auckland", "Australia/Adelaide", "UTC",
    "Not/AZone", "Invalid",
]

# DST の切り替え日をまたぐ基準時刻も混ぜる
BASE_TIMES = [
    datetime(2026, 1, 15, 3, 0, tzinfo=timezone.utc),
    datetime(2026, 3, 8, 9, 0, tzinfo=timezone.utc),
    datetime(2026, 3, 29, 1, 0, tzinfo=timezone.utc),
    datetime(2026, 7, 21, 15, 0, tzinfo=timezone.utc),
    datetime(2026, 8, 27, 1, 0, tzinfo=timezone.utc),
    datetime(2026, 11, 1, 6, 0, tzinfo=timezone.utc),
    datetime(2026, 12, 31, 23, 30, tzinfo=timezone.utc),
]


def ts(dt):
    """datetime をエポックミリ秒（Go 側で time.Time に戻す）に。"""
    return None if dt is None else int(dt.timestamp() * MS)


def main():
    rng = random.Random(20260827)
    cases = []

    # --- local_hour / local_date ---
    tz_cases = []
    for tz in TIMEZONES:
        for base in BASE_TIMES:
            tz_cases.append({
                "timezone": tz,
                "now": ts(base),
                "local_hour": local_hour(tz, base),
                "local_date": local_date(tz, base),
            })

    # --- 判定ロジック ---
    for _ in range(6000):
        now = rng.choice(BASE_TIMES)
        data = {}

        if rng.random() < 0.8:
            data["tier"] = rng.choice(["free", "premium"])
        if rng.random() < 0.7:
            data["timezone"] = rng.choice(TIMEZONES)
        if rng.random() < 0.8:
            data["preferred_generation_hour"] = rng.choice(
                [0, 3, 10, 12, 23, local_hour(data.get("timezone"), now)]
            )
        if rng.random() < 0.8:
            data["remaining_sentences"] = rng.choice([-1, 0, 1, 5, 20])
        if rng.random() < 0.7:
            data["notify_tier"] = rng.choice([0, 1, 2, 3, TIER_STOPPED, 9])
        if rng.random() < 0.7:
            data["notify_tier_misses"] = rng.choice([0, 1, 2, 3, 5])
        if rng.random() < 0.6:
            data["daily_reminder_enabled"] = rng.choice([True, False])
        if rng.random() < 0.8:
            data["fcm_token"] = rng.choice(["", "tok-1", "tok-2"])
        if rng.random() < 0.5:
            data["daily_sentence_generated"] = rng.choice([True, False])
        if rng.random() < 0.6:
            data["estimated_vocab"] = rng.choice([0, 1, 50, 300])

        # 時刻系。段階の閾値（1/3/10/30日）をまたぐ差分を意図的に置く
        if rng.random() < 0.75:
            days = rng.choice([0, 1, 2, 3, 4, 9, 10, 11, 29, 30, 31])
            hours = rng.choice([0, 1, -1])
            data["last_notified_at"] = now - timedelta(days=days, hours=hours)
        if rng.random() < 0.6:
            offset = rng.choice([-2, -1, 0, 1, 2])
            base = data.get("last_notified_at", now)
            data["last_sentence_generated_at"] = base + timedelta(hours=offset)
        if rng.random() < 0.5:
            offset = rng.choice([-2, -1, 0, 1, 2])
            base = data.get("last_notified_at", now)
            data["last_opened_at"] = base + timedelta(hours=offset)
        if rng.random() < 0.5:
            data["premium_trial_expires_at"] = now + timedelta(
                days=rng.choice([-3, -1, 0, 1, 3])
            )

        evaluated = evaluate_response(data)
        cases.append({
            "now": ts(now),
            "data": {
                k: (ts(v) if isinstance(v, datetime) else v)
                for k, v in data.items()
            },
            "timestamp_fields": [
                k for k, v in data.items() if isinstance(v, datetime)
            ],
            "has_generation_history": has_generation_history(data),
            "is_due": is_due(data, now),
            "evaluate_response": {
                "notify_tier": evaluated["notify_tier"],
                "notify_tier_misses": evaluated["notify_tier_misses"],
            },
            "uses_premium_trial": uses_premium_trial(data, now),
            "delivery_skip_reason": delivery_skip_reason(data, now),
        })

    out = os.path.join(os.path.dirname(__file__), "golden.json")
    with open(out, "w") as f:
        json.dump({"tz_cases": tz_cases, "cases": cases}, f, ensure_ascii=False)

    from collections import Counter
    reasons = Counter(c["delivery_skip_reason"] for c in cases)
    print(f"wrote tz={len(tz_cases)} cases={len(cases)} -> {out}", file=sys.stderr)
    for k, v in sorted(reasons.items(), key=lambda kv: -kv[1]):
        print(f"  {str(k):20} {v}", file=sys.stderr)


main()
