"""prod GA4 コホートリテンション（真のN日/N週リテンション）

first_open を起点に、N日後/N週後に実際に戻ってきた割合を出す。
Firestore版（prod_analytics.py）の「生存期間>=N日」とは定義が違うので注意。

usage:
  uv run python scripts/ga4_retention.py [weekly|daily]   # default weekly
  # 認証は SA インパーソネーション（project_ga4_data_api 参照）
"""

import subprocess
import sys
import json
from datetime import date, timedelta
from collections import defaultdict

PROP = "534357716"  # thai-memo-prod GA4
SA = "ga4-analytics@thai-memo-prod.iam.gserviceaccount.com"
MODE = sys.argv[1] if len(sys.argv) > 1 else "weekly"


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


def post(tok: str, body: dict) -> dict:
    url = f"https://analyticsdata.googleapis.com/v1beta/properties/{PROP}:runReport"
    out = subprocess.run(
        ["curl", "-s", url,
         "-H", f"Authorization: Bearer {tok}",
         "-H", "Content-Type: application/json",
         "-d", json.dumps(body)],
        capture_output=True, text=True,
    )
    d = json.loads(out.stdout)
    if "error" in d:
        sys.exit(json.dumps(d["error"], ensure_ascii=False)[:500])
    return d


def cohort_body(granularity: str, n: int, span: int) -> dict:
    """GA4 は cohort の startDate に YYYY-MM-DD しか受け付けない。
    さらに WEEKLY は日曜始まり・土曜終わりの週境界に揃える必要がある。"""
    unit = "Week" if granularity == "WEEKLY" else "Day"
    today = date.today()
    cohorts = []
    if granularity == "WEEKLY":
        # 直近の日曜（今週の開始）
        cur_sun = today - timedelta(days=(today.weekday() + 1) % 7)
        for i in range(n, 0, -1):
            s = cur_sun - timedelta(weeks=i - 1)
            e = s + timedelta(days=6)
            cohorts.append({
                "name": f"c{n - i}",
                "dimension": "firstSessionDate",
                "dateRange": {"startDate": s.isoformat(), "endDate": e.isoformat()},
            })
    else:
        for i in range(n, 0, -1):
            s = today - timedelta(days=i)
            cohorts.append({
                "name": f"c{n - i}",
                "dimension": "firstSessionDate",
                "dateRange": {"startDate": s.isoformat(), "endDate": s.isoformat()},
            })
    return {
        "cohortSpec": {
            "cohorts": cohorts,
            "cohortsRange": {"granularity": granularity, "startOffset": 0,
                             "endOffset": 8 if granularity == "WEEKLY" else 14},
        },
        "dimensions": [{"name": "cohort"}, {"name": f"cohortNth{unit}"}],
        "metrics": [{"name": "cohortActiveUsers"}],
    }


def main():
    tok = token()
    if MODE == "weekly":
        n, gran, span, label = 10, "WEEKLY", 7, "W"
    else:
        n, gran, span, label = 21, "DAILY", 1, "D"

    body = cohort_body(gran, n, span)
    # cohort名 -> 実日付レンジを控えておく
    ranges = {c["name"]: (c["dateRange"]["startDate"], c["dateRange"]["endDate"])
              for c in body["cohortSpec"]["cohorts"]}
    d = post(tok, body)

    t: dict[str, dict[int, int]] = defaultdict(dict)
    for r in d.get("rows", []):
        cn = r["dimensionValues"][0]["value"]
        nth = int(r["dimensionValues"][1]["value"].split("_")[-1])
        t[cn][nth] = int(r["metricValues"][0]["value"])

    maxn = body["cohortSpec"]["cohortsRange"]["endOffset"]
    cols = list(range(0, maxn + 1))
    print(f"=== GA4 Cohort Retention ({gran}, first_open 起点) ===")
    print(f"{'cohort':>16} {'N':>5} " + " ".join(f"{label}{i:<4d}" for i in cols))
    for cn in sorted(t, key=lambda x: int(x[1:])):
        row = t[cn]
        base = row.get(0, 0)
        if base == 0:
            continue
        s, e = ranges[cn]
        cells = []
        for i in cols:
            if i == 0:
                cells.append("100% ")
            elif i in row:
                cells.append(f"{row[i] / base * 100:3.0f}% ")
            else:
                cells.append("  -  ")
        print(f"{s.replace('daysAgo', 'd'):>16} {base:5d} " + " ".join(cells))
    print("\n注: 列は起点からの経過(週/日)。空欄は未到達期間。N<10 はノイズ。")


if __name__ == "__main__":
    main()
