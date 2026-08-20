"""prod GA4 にイベントスコープのカスタムディメンションを登録する。

GA4 は登録していないイベントパラメータを `(not set)` で返し、**登録は遡及しない**。
新しい文字列パラメータを `_logEvent` に足したら、その場でこれを実行する。

数値パラメータはここでは登録できない（customMetric 側が要る）。文字列を
customMetric に、数値を customDimension に登録すると、どちらも永遠に (not set)
になるので型を必ず確認すること。

usage:
  uv run python scripts/ga4_register_dimension.py announcement_id [表示名]
  uv run python scripts/ga4_register_dimension.py --list

前提: gcloud で下記SAへの tokenCreator 権限があること。
  ga4-analytics@thai-memo-prod.iam.gserviceaccount.com
"""

import json
import subprocess
import sys

PROP = "534357716"  # thai-memo-prod GA4
SA = "ga4-analytics@thai-memo-prod.iam.gserviceaccount.com"
BASE = f"https://analyticsadmin.googleapis.com/v1beta/properties/{PROP}/customDimensions"


def token() -> str:
    out = subprocess.run(
        ["gcloud", "auth", "print-access-token",
         f"--impersonate-service-account={SA}",
         "--scopes=https://www.googleapis.com/auth/analytics.edit"],
        capture_output=True, text=True,
    )
    if out.returncode != 0 or len(out.stdout.strip()) < 50:
        sys.exit(f"token error: {out.stderr[:300]}")
    return out.stdout.strip()


def curl(tok: str, url: str, body: dict | None = None) -> dict:
    cmd = ["curl", "-s", "-H", f"Authorization: Bearer {tok}"]
    if body is not None:
        cmd += ["-H", "Content-Type: application/json", "-d", json.dumps(body)]
    cmd.append(url)
    return json.loads(subprocess.run(cmd, capture_output=True, text=True).stdout)


def main() -> None:
    tok = token()
    args = sys.argv[1:]
    if not args or args[0] == "--list":
        for d in curl(tok, f"{BASE}?pageSize=60").get("customDimensions", []):
            print(f"  {d['parameterName']:24s} {d['name']}")
        return

    param = args[0]
    display = args[1] if len(args) > 1 else param
    res = curl(tok, BASE, {
        "parameterName": param,
        "displayName": display,
        "scope": "EVENT",
    })
    if "error" in res:
        # 409 ALREADY_EXISTS は登録済み。同じ名前をメトリクス側にも登録することは
        # できないので、型を取り違えていた場合は archive してから作り直す。
        sys.exit(f"failed: {res['error'].get('message')}")
    print(f"registered: {res['parameterName']} -> {res['name']}")


if __name__ == "__main__":
    main()
