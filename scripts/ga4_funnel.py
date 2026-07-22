"""prod GA4 新規ユーザー活性化ファネル（日次）

first_open → onboarding_start → generate_sentence の日次推移を出す。
ログイン壁/オンボ改善の先行指標。ただし新規流入が少ない時は数値がノイズになる点に注意。

usage:
  uv run python scripts/ga4_funnel.py [days]   # default 35
  # 認証は SA インパーソネーション（project_ga4_data_api 参照）

前提: gcloud で下記SAへの tokenCreator 権限があること。
  ga4-analytics@thai-memo-prod.iam.gserviceaccount.com
"""

import subprocess
import sys
import json
from collections import defaultdict

PROP = "534357716"  # thai-memo-prod GA4
SA = "ga4-analytics@thai-memo-prod.iam.gserviceaccount.com"
DAYS = int(sys.argv[1]) if len(sys.argv) > 1 else 35


def token() -> str:
    out = subprocess.run(
        ["gcloud", "auth", "print-access-token",
         f"--impersonate-service-account={SA}",
         "--scopes=https://www.googleapis.com/auth/analytics.readonly"],
        capture_output=True, text=True,
    )
    if out.returncode != 0 or len(out.stdout.strip()) < 50:
        sys.exit(f"token error: {out.stderr[:300]}")
    return out.stdout.strip()


def run_report(tok: str) -> dict:
    body = {
        "dateRanges": [{"startDate": f"{DAYS}daysAgo", "endDate": "today"}],
        "dimensions": [{"name": "date"}, {"name": "eventName"}],
        "metrics": [{"name": "totalUsers"}],
        "dimensionFilter": {"filter": {"fieldName": "eventName", "inListFilter": {
            "values": ["first_open", "onboarding_start", "onboarding_complete", "generate_sentence"]}}},
        "orderBys": [{"dimension": {"dimensionName": "date"}}],
    }
    url = f"https://analyticsdata.googleapis.com/v1beta/properties/{PROP}:runReport"
    out = subprocess.run(
        ["curl", "-s", url,
         "-H", f"Authorization: Bearer {tok}",
         "-H", "Content-Type: application/json",
         "-d", json.dumps(body)],
        capture_output=True, text=True,
    )
    return json.loads(out.stdout)


def main():
    d = run_report(token())
    t: dict[str, dict] = defaultdict(dict)
    for r in d.get("rows", []):
        dt = r["dimensionValues"][0]["value"]
        ev = r["dimensionValues"][1]["value"]
        t[dt][ev] = int(r["metricValues"][0]["value"])

    print(f"=== GA4 Activation Funnel (last {DAYS}d, by new users) ===")
    print(f"{'date':>10} {'first_open':>10} {'onb_start':>9} {'onb_done':>8} {'gen':>5} {'wall%':>6}")
    tot = defaultdict(int)
    for dt in sorted(t):
        a = t[dt].get("first_open", 0)
        b = t[dt].get("onboarding_start", 0)
        c = t[dt].get("onboarding_complete", 0)
        g = t[dt].get("generate_sentence", 0)
        for k, v in (("fo", a), ("os", b), ("oc", c), ("g", g)):
            tot[k] += v
        w = f"{b/a*100:.0f}%" if a else "-"
        print(f"{dt:>10} {a:>10} {b:>9} {c:>8} {g:>5} {w:>6}")
    print("-" * 52)
    fo = tot["fo"]
    wall = f"{tot['os']/fo*100:.0f}%" if fo else "-"
    print(f"{'TOTAL':>10} {fo:>10} {tot['os']:>9} {tot['oc']:>8} {tot['g']:>5} {wall:>6}")
    if fo:
        print(f"\n注意: 新規 first_open={fo}/{DAYS}d。母数が小さいと wall% はノイズ。")


if __name__ == "__main__":
    main()
