"""Google Play Console の、リリース以外の操作を API で行うスクリプト。

リリース（トラック・公開・段階公開）は play_release.py。こちらはそれ以外。

usage:
  python3 scripts/play_console.py testers [track]                  # テスターの Google グループ
  python3 scripts/play_console.py testers <track> --groups a@x,b@y # 置き換える（書き込み）
  python3 scripts/play_console.py listing [lang]                   # ストア掲載文（文字数つき）
  python3 scripts/play_console.py listing-set <lang> [--title T] [--short S] [--full-file F]
  python3 scripts/play_console.py images <lang>                    # 画像の種類ごとの枚数
  python3 scripts/play_console.py images-upload <lang> <type> <file>... [--replace]
  python3 scripts/play_console.py reviews                          # 直近のレビュー（API は約1週間分）
  python3 scripts/play_console.py reply <reviewId> <text>          # レビューに返信（公開される）
  python3 scripts/play_console.py products                         # サブスク・買い切りの状態と JP 価格
  python3 scripts/play_console.py vitals                           # 直近28日のクラッシュ率・ANR率
  書き込み系は --dry-run で commit しない（reply は --dry-run で送らない）

API で取れないもの: クローズドテストのオプトイン人数・14日の進み具合、本番アクセスの申請。
これらは Console で見る。

前提: play_release.py と同じサービスアカウント。vitals は prod プロジェクトで
      playdeveloperreporting.googleapis.com が有効であること。
"""

import argparse
import subprocess
import sys
from datetime import date, timedelta
from pathlib import Path

from play_release import BASE, PACKAGE, call, token

UPLOAD = BASE.replace("/androidpublisher/v3/", "/upload/androidpublisher/v3/")
REPORTING = f"https://playdeveloperreporting.googleapis.com/v1beta1/apps/{PACKAGE}"
REPORTING_SCOPE = "https://www.googleapis.com/auth/playdeveloperreporting"
LIMITS = {"title": 30, "shortDescription": 80, "fullDescription": 4000}
IMAGE_TYPES = ["icon", "featureGraphic", "phoneScreenshots", "sevenInchScreenshots",
               "tenInchScreenshots", "tvBanner", "tvScreenshots", "wearScreenshots"]


def price(p: dict | None) -> str:
    if not p:
        return "-"
    return f"{p.get('currencyCode', '')} {int(p.get('units', 0)) + p.get('nanos', 0) / 1e9:g}"


def upload(tok: str, path: str, file: Path) -> None:
    out = subprocess.run(
        ["curl", "-sS", "-X", "POST", f"{UPLOAD}{path}?uploadType=media",
         "-H", f"Authorization: Bearer {tok}", "-H", "Content-Type: image/png",
         "--data-binary", f"@{file}", "-w", "\n%{http_code}"],
        capture_output=True, text=True,
    )
    text, _, code = out.stdout.rpartition("\n")
    if not code.startswith("2"):
        sys.exit(f"upload {file} -> {code}\n{text[:500]}")


def cmd_testers(tok: str, edit: str, a) -> bool:
    if a.groups is None:
        tracks = a.args or [t["track"] for t in call(tok, "GET", f"/edits/{edit}/tracks")["tracks"]
                            if t["track"] != "production"]
        for t in tracks:
            groups = call(tok, "GET", f"/edits/{edit}/testers/{t}").get("googleGroups", [])
            print(f"{t}: {', '.join(groups) or '-'}")
        return False
    (track,) = a.args
    groups = [g.strip() for g in a.groups.split(",") if g.strip()]
    call(tok, "PUT", f"/edits/{edit}/testers/{track}", {"googleGroups": groups})
    print(f"{track} -> {', '.join(groups)}")
    return True


def cmd_listing(tok: str, edit: str, a) -> bool:
    for l in call(tok, "GET", f"/edits/{edit}/listings").get("listings", []):
        if a.args and l["language"] != a.args[0]:
            continue
        print(f"[{l['language']}]")
        for k, lim in LIMITS.items():
            v = l.get(k, "")
            print(f"  {k} ({len(v)}/{lim}):" + ("\n    " + v.replace("\n", "\n    ") if k == "fullDescription" else f" {v}"))
    return False


def cmd_listing_set(tok: str, edit: str, a) -> bool:
    (lang,) = a.args
    body = {"title": a.title, "shortDescription": a.short,
            "fullDescription": Path(a.full_file).read_text().strip() if a.full_file else None}
    body = {k: v for k, v in body.items() if v is not None}
    if not body:
        sys.exit("--title / --short / --full-file のどれかを指定する")
    for k, v in body.items():
        if len(v) > LIMITS[k]:
            sys.exit(f"{k} が {len(v)} 文字（上限 {LIMITS[k]}）")
    call(tok, "PATCH", f"/edits/{edit}/listings/{lang}", body)
    print(f"[{lang}] {', '.join(f'{k}={len(v)}字' for k, v in body.items())}")
    return True


def cmd_images(tok: str, edit: str, a) -> bool:
    (lang,) = a.args
    for t in IMAGE_TYPES:
        n = len(call(tok, "GET", f"/edits/{edit}/listings/{lang}/{t}").get("images", []))
        if n:
            print(f"{t}: {n}")
    return False


def cmd_images_upload(tok: str, edit: str, a) -> bool:
    lang, kind, *files = a.args
    if kind not in IMAGE_TYPES:
        sys.exit(f"type は {', '.join(IMAGE_TYPES)} のどれか")
    paths = [Path(f) for f in files]
    if missing := [str(p) for p in paths if not p.is_file()]:
        sys.exit(f"ファイルが無い: {', '.join(missing)}")
    if a.replace:
        call(tok, "DELETE", f"/edits/{edit}/listings/{lang}/{kind}")
    for p in paths:
        upload(tok, f"/edits/{edit}/listings/{lang}/{kind}", p)
    print(f"[{lang}] {kind}: {len(paths)}枚{'（既存を置き換え）' if a.replace else '追加'}")
    return True


def cmd_reviews(tok: str, a) -> None:
    reviews = call(tok, "GET", "/reviews?maxResults=100").get("reviews", [])
    if not reviews:
        print("直近のレビューなし（API が返すのは約1週間以内に書かれ・更新されたものだけ）")
    for r in reviews:
        user = next((c["userComment"] for c in r["comments"] if "userComment" in c), {})
        dev = next((c["developerComment"] for c in r["comments"] if "developerComment" in c), None)
        print(f"{r['reviewId']} ★{user.get('starRating', '?')} v{user.get('appVersionName', '?')} "
              f"{r.get('authorName', '')}")
        print(f"  {user.get('text', '').strip()}")
        if dev:
            print(f"  ↳ 返信済: {dev.get('text', '').strip()}")


def cmd_reply(tok: str, a) -> None:
    review_id, text = a.args
    if len(text) > 350:
        sys.exit(f"返信が {len(text)} 文字（上限 350）")
    print(f"{review_id} <- {text}")
    if a.dry_run:
        print("dry-run: 送らない")
        return
    call(tok, "POST", f"/reviews/{review_id}:reply", {"replyText": text})
    print("replied")


def cmd_products(tok: str, a) -> None:
    for s in call(tok, "GET", "/subscriptions").get("subscriptions", []):
        print(f"[sub] {s['productId']}")
        for b in s.get("basePlans", []):
            jp = next((c for c in b.get("regionalConfigs", []) if c["regionCode"] == "JP"), {})
            print(f"  {b['basePlanId']} {b.get('state', '?')} JP {price(jp.get('price'))}")
    for o in call(tok, "GET", "/oneTimeProducts").get("oneTimeProducts", []):
        print(f"[one-time] {o['productId']}")
        for opt in o.get("purchaseOptions", []):
            jp = next((c for c in opt.get("regionalPricingAndAvailabilityConfigs", [])
                       if c["regionCode"] == "JP"), {})
            print(f"  {opt.get('purchaseOptionId', '?')} {opt.get('state', '?')} JP {price(jp.get('price'))}")


def cmd_vitals(a) -> None:
    tok = token(REPORTING_SCOPE)
    for name, metrics in [
        ("crashRateMetricSet", ["crashRate28dUserWeighted", "userPerceivedCrashRate28dUserWeighted"]),
        ("anrRateMetricSet", ["anrRate28dUserWeighted", "userPerceivedAnrRate28dUserWeighted"]),
    ]:
        fresh = call(tok, "GET", f"{REPORTING}/{name}")["freshnessInfo"]["freshnesses"]
        end = next(f["latestEndTime"] for f in fresh if f["aggregationPeriod"] == "DAILY")
        start = {k: end[k] for k in ("year", "month", "day", "timeZone")}
        # DAILY の1日分。28d 系の指標はその日までの28日間の値になる
        d = date(end["year"], end["month"], end["day"]) - timedelta(days=1)
        start.update(year=d.year, month=d.month, day=d.day)
        body = {"timelineSpec": {"aggregationPeriod": "DAILY", "startTime": start, "endTime": end},
                "metrics": metrics + ["distinctUsers"]}
        rows = call(tok, "POST", f"{REPORTING}/{name}:query", body).get("rows", [])
        if not rows:
            print(f"{name}: データなし（利用者が少ないうちは Play が集計しない）")
            continue
        vals = {m["metric"]: m.get("decimalValue", {}).get("value", "-") for m in rows[-1]["metrics"]}
        t = rows[-1]["startTime"]
        print(f"{name.removesuffix('MetricSet')} ({t['year']}-{t['month']:02d}-{t['day']:02d}まで28日): "
              + ", ".join(f"{m}={vals.get(m, '-')}" for m in metrics)
              + f", users={vals.get('distinctUsers', '-')}")


EDIT_CMDS = {"testers": cmd_testers, "listing": cmd_listing, "listing-set": cmd_listing_set,
             "images": cmd_images, "images-upload": cmd_images_upload}


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("cmd", choices=[*EDIT_CMDS, "reviews", "reply", "products", "vitals"])
    p.add_argument("args", nargs="*")
    p.add_argument("--groups")
    p.add_argument("--title")
    p.add_argument("--short")
    p.add_argument("--full-file")
    p.add_argument("--replace", action="store_true")
    p.add_argument("--dry-run", action="store_true")
    a = p.parse_args()

    if a.cmd == "vitals":
        cmd_vitals(a)
        return
    tok = token()
    if a.cmd not in EDIT_CMDS:
        {"reviews": cmd_reviews, "reply": cmd_reply, "products": cmd_products}[a.cmd](tok, a)
        return

    edit = call(tok, "POST", "/edits", {})["id"]
    try:
        if not EDIT_CMDS[a.cmd](tok, edit, a):
            return
        if a.dry_run:
            print("dry-run: commit しない")
            return
        call(tok, "POST", f"/edits/{edit}:commit")
        edit = None
        print("committed")
    finally:
        if edit:
            call(tok, "DELETE", f"/edits/{edit}")


if __name__ == "__main__":
    main()
