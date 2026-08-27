"""prod GA4 初回起動時の言語決定の内訳。

`app_language_resolved` を storefront（ストア地域）× lang（決定されたUI言語）×
country（GA4のIP判定国）で割り、下記2つの取り違えを検出する。

  - storefront=unknown → ストア地域の取得失敗。fromStorefront が空文字を受けて
    ja を返すため（app_language.dart:36）、日本以外のユーザーが日本語UIで起動する。
  - country と lang の食い違い → 日本のユーザーが英語UI、その逆など。

`app_language_resolved` は新規インストール1人につき1回しか出ない
（settings_provider.dart:218 で stored != null なら早期return）ので、
ここでの母数はそのまま「期間内の新規インストール数」になる。

storefront / lang は 2026-08-27 にカスタムディメンション登録済み。
**GA4 の登録は遡及しない**ので、それ以前は全て (not set) で返る。

usage:
  uv run python scripts/ga4_language_resolution.py [days]   # default 28
  # 認証は SA インパーソネーション（project_ga4_data_api 参照）

前提: gcloud で下記SAへの tokenCreator 権限があること。
  ga4-analytics@thai-memo-prod.iam.gserviceaccount.com
"""

import json
import subprocess
import sys
from collections import defaultdict

PROP = "534357716"  # thai-memo-prod GA4
SA = "ga4-analytics@thai-memo-prod.iam.gserviceaccount.com"
DAYS = int(sys.argv[1]) if len(sys.argv) > 1 else 28

# 日本語UIで起動するストアフロント。ここ以外は英語UI。app_language.dart:37 と揃える。
JP_STOREFRONTS = {"JP", "JPN"}


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


def run_report(tok: str, dims: list[str]) -> dict:
    body = {
        "dateRanges": [{"startDate": f"{DAYS}daysAgo", "endDate": "today"}],
        "dimensions": [{"name": d} for d in dims],
        "metrics": [{"name": "totalUsers"}],
        "dimensionFilter": {"filter": {
            "fieldName": "eventName",
            "stringFilter": {"value": "app_language_resolved"},
        }},
        "limit": 500,
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


def rows(d: dict) -> list[tuple[list[str], int]]:
    return [
        ([v["value"] for v in r["dimensionValues"]], int(r["metricValues"][0]["value"]))
        for r in d.get("rows", [])
    ]


def main() -> None:
    tok = token()

    # 1. storefront の取得失敗率
    sf = defaultdict(int)
    for (store,), n in rows(run_report(tok, ["customEvent:storefront"])):
        sf[store] += n
    # (not set) はディメンション登録前に発火した分。比率の分母に入れると
    # 取得失敗率が実際より低く出るので、集計から外して件数だけ別に出す。
    notset = sf.pop("(not set)", 0)
    total = sum(sf.values())

    print(f"=== 言語決定の内訳 (last {DAYS}d, 新規インストール={total + notset}) ===")
    if notset:
        print(f"うち {notset} 件はディメンション登録前の発火で内訳を取れない"
              "（GA4 の登録は遡及しない）。以下は残り {} 件の集計。".format(total))
    if not total:
        print("\n内訳の取れるデータがまだない。登録後の新規インストールを待つこと。")
        return

    print("\n-- storefront --")
    unknown = sf.get("unknown", 0)
    for store, n in sorted(sf.items(), key=lambda x: -x[1]):
        print(f"  {store:<14}{n:>5}  {n/total*100:>5.1f}%")
    print(f"\n  取得失敗(unknown): {unknown}/{total} = {unknown/total*100:.1f}%"
          "  → 全員が日本語UIで起動")

    # 2. country × lang の食い違い
    print("\n-- country x lang (UIとユーザーの居場所の食い違い) --")
    print(f"  {'country':<20}{'lang':<6}{'users':>6}")
    mism_en_in_jp = 0   # 日本にいるのに英語UI
    mism_ja_outside = 0  # 日本の外なのに日本語UI
    for (country, lang), n in sorted(
        rows(run_report(tok, ["country", "customEvent:lang"])), key=lambda x: -x[1]
    ):
        flag = ""
        if lang == "(not set)":
            pass  # 登録前の分。食い違いは判定できない。
        elif country == "Japan" and lang == "en":
            flag, mism_en_in_jp = "  <- 日本で英語UI", mism_en_in_jp + n
        elif country != "Japan" and lang == "ja":
            flag, mism_ja_outside = "  <- 日本国外で日本語UI", mism_ja_outside + n
        print(f"  {country[:19]:<20}{lang:<6}{n:>6}{flag}")
    print(f"\n  日本で英語UI      : {mism_en_in_jp}")
    print(f"  日本国外で日本語UI: {mism_ja_outside}  （うち多くは storefront 取得失敗）")

    # 3. storefront と lang の整合性（マッピングのバグ検出）
    print("\n-- storefront x lang の整合性 --")
    bad = 0
    for (store, lang), n in sorted(
        rows(run_report(tok, ["customEvent:storefront", "customEvent:lang"])),
        key=lambda x: -x[1],
    ):
        if store == "(not set)" or lang == "(not set)":
            continue  # 登録前の分。整合性は判定できない。
        expect = "ja" if (store.upper() in JP_STOREFRONTS or store == "unknown") else "en"
        ok = "" if lang == expect else f"  <- 想定は {expect}"
        if ok:
            bad += n
        print(f"  {store:<14}{lang:<6}{n:>5}{ok}")
    if bad:
        print(f"\n  想定と違う組み合わせ: {bad} 件。fromStorefront の分岐を確認すること。")

    print(f"\n注意: 内訳の取れる新規={total}/{DAYS}d。母数が小さいと各比率はノイズ。")


if __name__ == "__main__":
    main()
