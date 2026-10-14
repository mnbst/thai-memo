"""prod GA4 新規ユーザー活性化ファネル。

GA4 Funnel Report API の閉じたファネルを使い、同じユーザーが期間内に
STEPS の順で
到達した人数を集計する。独立したイベント人数を割らないため100%を超えない。

usage:
  uv run python scripts/ga4_funnel.py [days]            # default 35
  uv run python scripts/ga4_funnel.py [days] --startup  # 起動〜機能紹介の内訳
"""

from __future__ import annotations

import json
import subprocess
import sys

PROP = "534357716"
SA = "ga4-analytics@thai-memo-prod.iam.gserviceaccount.com"
DEFAULT_DAYS = 35
# (表示名, イベント名, {パラメータ: 値 | (値, ...)})。値を並べたものはどれか一つに一致。
# 初回導線の順: 機能紹介 → ヒアリング → 使い方ガイド → 語彙テスト → ペイウォール → 生成。
# 別端末のアカウントで入った人はヒアリング以降を通らないので、ここで落ちて見える。
STEPS = (
    ("first_open", "first_open", {}),
    ("onboarding_start", "onboarding_start", {}),
    ("onboarding_complete", "onboarding_complete", {}),
    ("interview_start", "interview", {"action": "start"}),
    ("interview_complete", "interview", {"action": ("complete", "skip")}),
    ("guide_open", "guide", {"action": "open", "source": "first_launch"}),
    # auto_skip はヒアリングが「まったく初めて」で出さなかった人。start と end の両方に数える。
    ("vocab_test_start", "vocab_test",
     {"action": ("start", "auto_skip"), "source": "onboarding"}),
    ("vocab_test_end", "vocab_test",
     {"action": ("complete", "skip", "auto_skip"), "source": "onboarding"}),
    ("generate_sentence", "generate_sentence", {}),
)

# --startup: first_open から機能紹介を読み終えるまで。startup / onboarding_page は
# 2026-10 のビルドから送るので、それより前に入った人はここで落ちて見える。
STARTUP_STEPS = (
    ("first_open", "first_open", {}),
    ("auth_start", "startup", {"action": "auth_start"}),
    ("auth_ok", "startup", {"action": "auth_ok"}),
    ("home_first_launch", "startup", {"action": "home", "value": "first_launch"}),
    ("onboarding_start", "onboarding_start", {}),
    ("onboarding_page_2", "onboarding_page", {"value": "2"}),
    ("onboarding_page_3", "onboarding_page", {"value": "3"}),
    ("onboarding_complete", "onboarding_complete", {}),
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


def step_filter(event_name: str, params: dict) -> dict:
    event_filter: dict = {"eventName": event_name}
    exprs = []
    for key, value in params.items():
        values = value if isinstance(value, tuple) else (value,)
        ors = [
            {"funnelParameterFilter": {
                "eventParameterName": key,
                "stringFilter": {"matchType": "EXACT", "value": v},
            }}
            for v in values
        ]
        exprs.append(ors[0] if len(ors) == 1 else {"orGroup": {"expressions": ors}})
    if exprs:
        event_filter["funnelParameterFilterExpression"] = (
            exprs[0] if len(exprs) == 1 else {"andGroup": {"expressions": exprs}})
    return {"funnelEventFilter": event_filter}


def run_report(access_token: str, days: int, steps: tuple = STEPS) -> dict:
    body = {
        "dateRanges": [{"startDate": f"{days}daysAgo", "endDate": "today"}],
        "funnel": {
            "isOpenFunnel": False,
            "steps": [
                {"name": name, "filterExpression": step_filter(event_name, params)}
                for name, event_name, params in steps
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
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    days = int(args[0]) if args else DEFAULT_DAYS
    steps = STARTUP_STEPS if "--startup" in sys.argv else STEPS
    report = run_report(token(), days, steps)
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
