"""prod GA4 新規ユーザー活性化ファネル。

GA4 Funnel Report API の閉じたファネルを使い、同じユーザーが期間内に
first_open → onboarding_start → onboarding_complete → generate_sentence の順で
到達した人数を集計する。独立したイベント人数を割らないため100%を超えない。

usage:
  uv run python scripts/ga4_funnel.py [days]  # default 35
"""

from __future__ import annotations

import json
import subprocess
import sys

PROP = "534357716"
SA = "ga4-analytics@thai-memo-prod.iam.gserviceaccount.com"
DEFAULT_DAYS = 35
STEPS = (
    "first_open",
    "onboarding_start",
    "onboarding_complete",
    "generate_sentence",
)


def token() -> str:
    result = subprocess.run(
        [
            "gcloud",
            "auth",
            "print-access-token",
            f"--impersonate-service-account={SA}",
            "--scopes=https://www.googleapis.com/auth/analytics.readonly",
        ],
        capture_output=True,
        text=True,
        check=False,
    )
    value = result.stdout.strip()
    if result.returncode != 0 or len(value) < 50:
        raise SystemExit(f"token error: {result.stderr[:300]}")
    return value


def run_report(access_token: str, days: int) -> dict:
    body = {
        "dateRanges": [{"startDate": f"{days}daysAgo", "endDate": "today"}],
        "funnel": {
            "isOpenFunnel": False,
            "steps": [
                {
                    "name": event_name,
                    "filterExpression": {
                        "funnelEventFilter": {"eventName": event_name}
                    },
                }
                for event_name in STEPS
            ],
        },
    }
    url = (
        "https://analyticsdata.googleapis.com/v1alpha/properties/"
        f"{PROP}:runFunnelReport"
    )
    result = subprocess.run(
        [
            "curl",
            "-sS",
            url,
            "-H",
            f"Authorization: Bearer {access_token}",
            "-H",
            "Content-Type: application/json",
            "-d",
            json.dumps(body),
        ],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        raise SystemExit(f"request error: {result.stderr[:300]}")
    try:
        report = json.loads(result.stdout)
    except json.JSONDecodeError:
        raise SystemExit(f"invalid GA4 response: {result.stdout[:300]}") from None
    if "error" in report:
        raise SystemExit(f"GA4 error: {report['error'].get('message')}")
    return report


def percentage(value: float) -> str:
    return f"{value * 100:.1f}%"


def parse_rows(report: dict) -> list[tuple[str, int, float, int]]:
    rows = report.get("funnelTable", {}).get("rows", [])
    parsed: list[tuple[str, int, float, int]] = []
    for row in rows:
        step = row["dimensionValues"][0]["value"].split(". ", 1)[-1]
        values = row["metricValues"]
        parsed.append(
            (
                step,
                int(values[0]["value"]),
                float(values[1]["value"]),
                int(values[2]["value"]),
            )
        )
    return parsed


def main() -> None:
    days = int(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_DAYS
    report = run_report(token(), days)
    parsed = parse_rows(report)
    if not parsed:
        print("No activation funnel data.")
        return

    base = parsed[0][1]
    print(f"=== GA4 Activation Funnel (closed, last {days}d) ===")
    print(f"{'step':<24} {'users':>7} {'from first':>11} {'to next':>9} {'drop':>7}")
    for step, users, completion_rate, abandonments in parsed:
        from_first = users / base if base else 0
        print(
            f"{step:<24} {users:>7} {percentage(from_first):>11} "
            f"{percentage(completion_rate):>9} {abandonments:>7}"
        )

    sampling = report.get("funnelTable", {}).get("metadata", {}).get(
        "samplingMetadatas", []
    )
    if sampling:
        item = sampling[0]
        print(
            "\n注意: sampled "
            f"{item.get('samplesReadCount')}/{item.get('samplingSpaceSize')} events"
        )


if __name__ == "__main__":
    main()
