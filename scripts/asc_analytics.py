"""App Store Connect Analytics Reports 取得スクリプト。

GA4 では流入元が全て (direct)/(none) になり経路が取れないため、
ストア側の真実（検索/ブラウズ/Web参照 別のダウンロード、検索キーワード）は
こちらで取る。

usage:
  uv run python scripts/asc_analytics.py                 # 利用可能レポート一覧
  uv run python scripts/asc_analytics.py <reportName>    # 該当レポートをCSV取得

レポート名は前方一致。Apple 側は同じレポートを
`App Downloads Standard` / `App Downloads Detailed` の2粒度で出すため、
`App Downloads` を渡すと両方取得する。
CSV の保存先はカレントディレクトリに依存せず常に <repo>/scripts/asc_data/。

前提: Secret Manager (thai-memo-prod) に appstore-key-id / appstore-issuer-id /
      appstore-connect-key が登録済み。skill: appstore-connect-inspect 参照。

Report Request は作成済み（Apple 側の生成に丸1日かかる方式）:
  ONE_TIME_SNAPSHOT 5739255e-98e0-4282-91fd-a665063868b2  # 過去1年分
  ONGOING           445ccad5-26ac-40b1-9384-2cfecd208424  # 日次継続
"""

import gzip
import json
import subprocess
import sys
import time
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = REPO_ROOT / "scripts" / "asc_data"

GCP_PROJECT = "thai-memo-prod"
APP_ID = "6759669680"
REQUESTS = {
    "snapshot": "5739255e-98e0-4282-91fd-a665063868b2",
    "ongoing": "445ccad5-26ac-40b1-9384-2cfecd208424",
}
BASE = "https://api.appstoreconnect.apple.com/v1"

# 経路把握で見るべきレポート名（Apple 側の命名）。
# 実際のレポート名には ` Standard` / ` Detailed` が付くため前方一致で判定する。
OF_INTEREST = [
    "App Store Discovery and Engagement",
    "App Store Search Terms",
    "App Downloads",
    "App Store Installation and Deletion",
]


def matches(name: str, prefixes: list[str]) -> bool:
    """`App Downloads` が `App Downloads Standard` に一致するよう前方一致で見る。"""
    return any(name == p or name.startswith(p + " ") for p in prefixes)


def secret(name: str) -> str:
    out = subprocess.run(
        ["gcloud", "secrets", "versions", "access", "latest",
         f"--secret={name}", f"--project={GCP_PROJECT}"],
        capture_output=True, text=True,
    )
    if out.returncode != 0:
        sys.exit(f"secret {name}: {out.stderr[:200]}")
    return out.stdout.strip()


def token() -> str:
    import jwt  # functions/python の venv に同梱
    payload = {
        "iss": secret("appstore-issuer-id"),
        "iat": int(time.time()),
        "exp": int(time.time()) + 1200,
        "aud": "appstoreconnect-v1",
    }
    return jwt.encode(
        payload, secret("appstore-connect-key"), algorithm="ES256",
        headers={"kid": secret("appstore-key-id")},
    )


def get(tok: str, url: str) -> dict:
    # venv の Python は証明書ストアを持たないため curl を使う
    out = subprocess.run(
        ["curl", "-g", "-sS", url, "-H", f"Authorization: Bearer {tok}"],
        capture_output=True, text=True,
    )
    if out.returncode != 0:
        raise RuntimeError(out.stderr[:200])
    data = json.loads(out.stdout)
    if "errors" in data:
        raise RuntimeError(data["errors"][0].get("detail", "unknown"))
    return data


def list_reports(tok: str) -> list[dict]:
    found = []
    for label, rid in REQUESTS.items():
        try:
            data = get(tok, f"{BASE}/analyticsReportRequests/{rid}/reports?limit=200")
        except Exception as e:  # まだ生成前は 404/空
            print(f"  {label}: not ready ({e})")
            continue
        rows = data.get("data", [])
        print(f"  {label}: {len(rows)} reports")
        for r in rows:
            a = r["attributes"]
            found.append({"id": r["id"], "name": a.get("name"),
                          "category": a.get("category"), "access": label})
    return found


def download(tok: str, report_id: str, name: str, access: str) -> None:
    """レポート -> インスタンス -> セグメント -> gz CSV を落とす。

    1インスタンスが複数セグメントに分割されることがあり、snapshot と ongoing で
    processingDate が重なることもあるため、access とセグメント連番でファイル名を分ける。
    """
    insts = get(tok, f"{BASE}/analyticsReports/{report_id}/instances?limit=200")
    safe = name.replace(" ", "_").replace("/", "-")
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for inst in insts.get("data", []):
        gran = inst["attributes"].get("granularity")
        date = inst["attributes"].get("processingDate")
        segs = get(tok, f"{BASE}/analyticsReportInstances/{inst['id']}/segments")
        for i, seg in enumerate(segs.get("data", []), start=1):
            url = seg["attributes"]["url"]
            stem = f"{safe}_{access}_{gran}_{date}"
            out = OUT_DIR / f"{stem}_{i:02d}.csv"
            n = 1
            while out.exists():  # 別インスタンスが同じ粒度・日付を返す場合の退避
                n += 1
                out = OUT_DIR / f"{stem}_{i:02d}-{n}.csv"
            raw = subprocess.run(
                ["curl", "-sS", "-L", url], capture_output=True
            ).stdout
            try:
                raw = gzip.decompress(raw)
            except OSError:
                pass
            out.write_bytes(raw)
            print(f"    saved {out.relative_to(REPO_ROOT)} ({len(raw)} bytes)")


def main() -> None:
    tok = token()
    print("== available reports ==")
    reports = list_reports(tok)
    if not reports:
        print("\nまだ生成されていません。作成から丸1日ほど待って再実行してください。")
        return

    target = sys.argv[1] if len(sys.argv) > 1 else None
    if not target:
        for r in reports:
            mark = "*" if matches(r["name"], OF_INTEREST) else " "
            print(f" {mark} [{r['access']}] {r['category']:<28} {r['name']}")
        print("\n* = 経路把握で見るもの。名前を引数に渡すとCSVを取得します（前方一致）。")
        return

    hits = [r for r in reports if matches(r["name"], [target])]
    if not hits:
        sys.exit(f"レポートが見つかりません: {target}（引数なしで一覧を確認してください）")
    for r in hits:
        print(f"\n== downloading {r['name']} ({r['access']}) ==")
        download(tok, r["id"], r["name"], r["access"])


if __name__ == "__main__":
    main()
