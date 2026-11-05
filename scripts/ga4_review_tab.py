"""prod GA4 の復習タブ利用状況を出す。読み取りのみ。

usage:
  uv run python scripts/ga4_review_tab.py              # 直近7日
  uv run python scripts/ga4_review_tab.py --days 30

review_tab イベントは、この計測が入ったビルドからしか集まらない。
screen_view の history は、タブと全例文の一覧の両方を含む。
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import urllib.request

PROP = "534357716"
SA = "ga4-analytics@thai-memo-prod.iam.gserviceaccount.com"
SCOPE = "https://www.googleapis.com/auth/analytics.readonly"
SCREENS = ["learning", "history", "vocab_word"]


def token() -> str:
    return subprocess.check_output(
        [
            "gcloud",
            "auth",
            "print-access-token",
            f"--impersonate-service-account={SA}",
            f"--scopes={SCOPE}",
        ],
        text=True,
        stderr=subprocess.DEVNULL,
    ).strip()


def report(tok: str, body: dict) -> list[list[str]]:
    req = urllib.request.Request(
        f"https://analyticsdata.googleapis.com/v1beta/properties/{PROP}:runReport",
        json.dumps(body).encode(),
        {"Authorization": f"Bearer {tok}", "Content-Type": "application/json"},
    )
    data = json.load(urllib.request.urlopen(req))
    return [
        [v["value"] for v in row["dimensionValues"]]
        + [v["value"] for v in row["metricValues"]]
        for row in data.get("rows", [])
    ]


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--days", type=int, default=7)
    args = parser.parse_args()
    os.environ.setdefault("SSL_CERT_FILE", "/etc/ssl/cert.pem")
    tok = token()
    dates = [{"startDate": f"{args.days}daysAgo", "endDate": "today"}]
    metrics = [{"name": "activeUsers"}, {"name": "eventCount"}]

    print(f"直近{args.days}日  列: ユーザー数 回数")
    print("\n[画面]")
    rows = report(
        tok,
        {
            "dateRanges": dates,
            "dimensions": [{"name": "appVersion"}, {"name": "unifiedScreenName"}],
            "metrics": metrics,
            "dimensionFilter": {
                "andGroup": {
                    "expressions": [
                        {
                            "filter": {
                                "fieldName": "eventName",
                                "stringFilter": {"value": "screen_view"},
                            }
                        },
                        {
                            "filter": {
                                "fieldName": "unifiedScreenName",
                                "inListFilter": {"values": SCREENS},
                            }
                        },
                    ]
                }
            },
            "orderBys": [{"dimension": {"dimensionName": "appVersion"}, "desc": True}],
            "limit": 60,
        },
    )
    for row in rows:
        print(" ".join(row))

    print("\n[review_tab]")
    rows = report(
        tok,
        {
            "dateRanges": dates,
            "dimensions": [
                {"name": "customEvent:action"},
                {"name": "customEvent:value"},
            ],
            "metrics": metrics,
            "dimensionFilter": {
                "filter": {
                    "fieldName": "eventName",
                    "stringFilter": {"value": "review_tab"},
                }
            },
            "limit": 60,
        },
    )
    for row in rows:
        print(" ".join(row))
    if not rows:
        print("まだデータなし")


if __name__ == "__main__":
    main()
