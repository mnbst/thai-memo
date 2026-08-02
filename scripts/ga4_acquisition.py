"""prod GA4 新規ユーザーの流入元。

「今週いきなり新規が増えた」ときに、どこから来たのかを特定する用途。
日次の first_open 推移と、流入元・国・OS・アプリバージョン別の内訳を出す。

usage:
  uv run python scripts/ga4_acquisition.py [days]   # default 14
  # 認証は SA インパーソネーション（memory: project_ga4_data_api 参照）

前提: gcloud で下記SAへの tokenCreator 権限があること。
  ga4-analytics@thai-memo-prod.iam.gserviceaccount.com
"""

import json
import subprocess
import sys

PROP = "534357716"  # thai-memo-prod GA4
SA = "ga4-analytics@thai-memo-prod.iam.gserviceaccount.com"
DAYS = int(sys.argv[1]) if len(sys.argv) > 1 else 14


def token() -> str:
    out = subprocess.run(
        [
            "gcloud", "auth", "print-access-token",
            f"--impersonate-service-account={SA}",
            "--scopes=https://www.googleapis.com/auth/analytics.readonly",
        ],
        capture_output=True,
        text=True,
    )
    if out.returncode != 0 or len(out.stdout.strip()) < 50:
        sys.exit(f"token error: {out.stderr[:300]}")
    return out.stdout.strip()


def run_report(tok: str, dimensions: list[str], metrics: list[str]) -> dict:
    body = {
        "dateRanges": [{"startDate": f"{DAYS}daysAgo", "endDate": "today"}],
        "dimensions": [{"name": d} for d in dimensions],
        "metrics": [{"name": m} for m in metrics],
        "orderBys": [{"metric": {"metricName": metrics[0]}, "desc": True}],
        "limit": 25,
    }
    # zsh の :r 修飾子と誤認されるため URL は f-string で組む（memory参照）
    url = f"https://analyticsdata.googleapis.com/v1beta/properties/{PROP}:runReport"
    out = subprocess.run(
        [
            "curl", "-s", url,
            "-H", f"Authorization: Bearer {tok}",
            "-H", "Content-Type: application/json",
            "-d", json.dumps(body),
        ],
        capture_output=True,
        text=True,
    )
    return json.loads(out.stdout)


def show(tok: str, label: str, dimensions: list[str], metrics: list[str]) -> None:
    data = run_report(tok, dimensions, metrics)
    if "error" in data:
        print(f"\n== {label} ==\n  error: {data['error'].get('message')}")
        return
    print(f"\n== {label} ==")
    rows = data.get("rows", [])
    if not rows:
        print("  (データなし)")
        return
    for r in rows:
        dims = " / ".join(v["value"] for v in r["dimensionValues"])
        vals = "  ".join(
            f"{m}={v['value']}" for m, v in zip(metrics, r["metricValues"])
        )
        print(f"  {dims:<48} {vals}")


def main() -> None:
    tok = token()
    print(f"prod GA4 直近{DAYS}日の流入")
    show(tok, "日次", ["date"], ["newUsers", "totalUsers"])
    show(tok, "流入元 (first user source/medium)",
         ["firstUserSourceMedium"], ["newUsers"])
    show(tok, "キャンペーン", ["firstUserCampaignName"], ["newUsers"])
    show(tok, "国", ["country"], ["newUsers"])
    show(tok, "OS", ["operatingSystem", "appVersion"], ["newUsers"])


if __name__ == "__main__":
    main()
