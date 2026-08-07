"""prod GA4 1問確認クイズ導線A/Bテスト集計。

quiz_offer の assigned → shown → tapped → started → answered を
実験群別に表示する。
率はイベント回数ではなく、各actionを実行したユニークユーザー数で
計算する。

usage:
  functions/python/.venv/bin/python scripts/ga4_quiz_offer_experiment.py \
    YYYY-MM-DD [YYYY-MM-DD|today]

開始日は実験版を公開した日を必ず指定する。assignedは端末ごとに一度だけなので、
直近N日のような移動窓では分母が欠ける。

前提: gcloud で下記SAへの tokenCreator 権限があること。
  ga4-analytics@thai-memo-prod.iam.gserviceaccount.com
"""

import json
import subprocess
import sys
from collections import defaultdict
from datetime import date


PROPERTY_ID = "534357716"
SERVICE_ACCOUNT = "ga4-analytics@thai-memo-prod.iam.gserviceaccount.com"
VARIANTS = ("learning_quiz_control_v1", "learning_quiz_inline_v1")
ACTIONS = ("assigned", "shown", "tapped", "started", "answered", "error")


def parse_date_range(args: list[str]) -> tuple[str, str]:
    if len(args) not in (2, 3):
        raise SystemExit("usage: ga4_quiz_offer_experiment.py START_DATE [END_DATE|today]")
    try:
        start = date.fromisoformat(args[1])
    except ValueError:
        raise SystemExit("START_DATE must be YYYY-MM-DD") from None

    end_arg = args[2] if len(args) == 3 else "today"
    if end_arg != "today":
        try:
            end = date.fromisoformat(end_arg)
        except ValueError:
            raise SystemExit("END_DATE must be YYYY-MM-DD or today") from None
        if end < start:
            raise SystemExit("END_DATE must not be earlier than START_DATE")
    return start.isoformat(), end_arg


def access_token() -> str:
    result = subprocess.run(
        [
            "gcloud",
            "auth",
            "print-access-token",
            f"--impersonate-service-account={SERVICE_ACCOUNT}",
            "--scopes=https://www.googleapis.com/auth/analytics.readonly",
        ],
        capture_output=True,
        text=True,
        check=False,
    )
    token = result.stdout.strip()
    if result.returncode != 0 or len(token) < 50:
        raise SystemExit(f"token error: {result.stderr[:300]}")
    return token


def run_report(token: str, start_date: str, end_date: str) -> dict:
    body = {
        "dateRanges": [{"startDate": start_date, "endDate": end_date}],
        "dimensions": [
            {"name": "customEvent:source"},
            {"name": "customEvent:action"},
        ],
        "metrics": [{"name": "totalUsers"}, {"name": "eventCount"}],
        "dimensionFilter": {
            "filter": {
                "fieldName": "eventName",
                "stringFilter": {"matchType": "EXACT", "value": "quiz_offer"},
            }
        },
        "limit": "100",
    }
    url = (
        "https://analyticsdata.googleapis.com/v1beta/properties/"
        f"{PROPERTY_ID}:runReport"
    )
    result = subprocess.run(
        [
            "curl",
            "-sS",
            url,
            "-H",
            f"Authorization: Bearer {token}",
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
        message = report["error"].get("message", str(report["error"]))
        raise SystemExit(f"GA4 error: {message}")
    return report


def percentage(numerator: int, denominator: int) -> str:
    if denominator == 0:
        return "-"
    return f"{numerator / denominator * 100:.1f}%"


def collect(
    report: dict,
) -> tuple[dict[str, dict[str, int]], dict[str, dict[str, int]]]:
    users: dict[str, dict[str, int]] = defaultdict(lambda: defaultdict(int))
    events: dict[str, dict[str, int]] = defaultdict(lambda: defaultdict(int))
    for row in report.get("rows", []):
        source = row["dimensionValues"][0]["value"]
        action = row["dimensionValues"][1]["value"]
        if source not in VARIANTS or action not in ACTIONS:
            continue
        users[source][action] = int(row["metricValues"][0]["value"])
        events[source][action] = int(row["metricValues"][1]["value"])
    return users, events


def print_report(report: dict, start_date: str, end_date: str) -> None:
    users, events = collect(report)
    print(f"=== Quiz offer A/B ({start_date} to {end_date}, unique users) ===")
    print(
        f"{'variant':<25} {'assign':>6} {'shown':>6} {'tap':>6} "
        f"{'start':>6} {'answer':>7} {'error':>6} "
        f"{'answer/assign':>13} {'answer/show':>12}"
    )
    for variant in VARIANTS:
        row = users[variant]
        assigned = row["assigned"]
        shown = row["shown"]
        tapped = row["tapped"]
        started = row["started"]
        answered = row["answered"]
        error = row["error"]
        print(
            f"{variant:<25} {assigned:>6} {shown:>6} {tapped:>6} "
            f"{started:>6} {answered:>7} {error:>6} "
            f"{percentage(answered, assigned):>13} "
            f"{percentage(answered, shown):>12}"
        )

    if not any(users[variant]["assigned"] for variant in VARIANTS):
        print("\nquiz_offer data is not available yet.")
        return

    print("\nFunnel rates (unique users):")
    print(
        f"{'variant':<25} {'shown/assign':>12} {'tap/shown':>10} "
        f"{'start/tap':>10} {'answer/start':>13} {'error/tap':>10}"
    )
    for variant in VARIANTS:
        row = users[variant]
        print(
            f"{variant:<25} "
            f"{percentage(row['shown'], row['assigned']):>12} "
            f"{percentage(row['tapped'], row['shown']):>10} "
            f"{percentage(row['started'], row['tapped']):>10} "
            f"{percentage(row['answered'], row['started']):>13} "
            f"{percentage(row['error'], row['tapped']):>10}"
        )

    print("\nEvent counts (diagnostic; conversion uses unique users):")
    for variant in VARIANTS:
        counts = ", ".join(
            f"{action}={events[variant][action]}" for action in ACTIONS
        )
        print(f"  {variant}: {counts}")


def main() -> None:
    start_date, end_date = parse_date_range(sys.argv)
    print_report(
        run_report(access_token(), start_date, end_date),
        start_date,
        end_date,
    )


if __name__ == "__main__":
    main()
