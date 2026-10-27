"""Google Play Developer API でリリースを操作するスクリプト。

CI（distribute-prod-android.yml）は AAB を draft で上げるだけなので、
公開・昇格・段階公開はここから行う。

usage:
  python3 scripts/play_release.py status                         # 全トラックのリリース一覧
  python3 scripts/play_release.py publish <track> [--fraction F] # track の draft を公開
  python3 scripts/play_release.py promote <from> <to> [--fraction F]
                                                                 # from の最新リリースを to へ
  python3 scripts/play_release.py rollout <track> --fraction F   # 段階公開の割合を変える
  python3 scripts/play_release.py rollout <track> --complete     # 段階公開を100%にする
  python3 scripts/play_release.py rollout <track> --halt         # 段階公開を止める
  python3 scripts/play_release.py next-code                      # 次に使う versionCode を出す
  共通: --notes "文言" で ja-JP のリリースノートを上書き、--dry-run で commit しない

--fraction を省くと completed（全員に配信）。Play の審査は API でも通常どおり入る。

前提: Secret Manager (thai-memo-prod) の ci-google-play-service-account に
      Play Console で「リリースの管理」権限を持つサービスアカウントの JSON がある。
      環境変数 PLAY_SERVICE_ACCOUNT_JSON があればそちらを使う（CI 用）。
"""

import argparse
import json
import os
import subprocess
import sys

GCP_PROJECT = "thai-memo-prod"
PACKAGE = "com.thaimemo.thai_memo"
BASE = f"https://androidpublisher.googleapis.com/androidpublisher/v3/applications/{PACKAGE}"
SCOPE = "https://www.googleapis.com/auth/androidpublisher"


def secret(name: str) -> str:
    out = subprocess.run(
        ["gcloud", "secrets", "versions", "access", "latest",
         f"--secret={name}", f"--project={GCP_PROJECT}"],
        capture_output=True, text=True,
    )
    if out.returncode != 0:
        sys.exit(f"secret {name}: {out.stderr[:200]}")
    return out.stdout


def token(scope: str = SCOPE) -> str:
    from google.auth.transport.requests import Request
    from google.oauth2 import service_account

    raw = os.environ.get("PLAY_SERVICE_ACCOUNT_JSON") or secret("ci-google-play-service-account")
    info = json.loads(raw)
    creds = service_account.Credentials.from_service_account_info(info, scopes=[scope])
    creds.refresh(Request())
    return creds.token


def call(tok: str, method: str, path: str, body: dict | None = None) -> dict:
    """path は BASE からの相対。http から始まれば完全な URL として扱う。"""
    # asc_analytics.py と同じく証明書ストアの差を避けて curl を使う
    url = path if path.startswith("http") else f"{BASE}{path}"
    cmd = ["curl", "-sS", "-X", method, url,
           "-H", f"Authorization: Bearer {tok}", "-H", "Content-Type: application/json",
           "-w", "\n%{http_code}"]
    if body is not None:
        cmd += ["-d", json.dumps(body)]
    out = subprocess.run(cmd, capture_output=True, text=True)
    if out.returncode != 0:
        sys.exit(out.stderr[:200])
    text, _, code = out.stdout.rpartition("\n")
    if not code.startswith("2"):
        sys.exit(f"{method} {path} -> {code}\n{text[:1000]}")
    return json.loads(text) if text.strip() else {}


def fmt(r: dict) -> str:
    frac = f" {r['userFraction']:.0%}" if "userFraction" in r else ""
    codes = ",".join(r.get("versionCodes", []))
    return f"{r.get('name', '?')} (code {codes}) {r['status']}{frac}"


def latest(releases: list[dict], status: str | None = None) -> dict:
    cands = [r for r in releases if status is None or r["status"] == status]
    if not cands:
        sys.exit(f"対象リリースが無い (status={status})")
    return max(cands, key=lambda r: max(int(c) for c in r.get("versionCodes", ["0"])))


def apply_target(r: dict, fraction: float | None, notes: str | None) -> dict:
    r = {k: v for k, v in r.items() if k in ("name", "versionCodes", "releaseNotes")}
    if fraction is None or fraction >= 1:
        r["status"] = "completed"
    else:
        r["status"] = "inProgress"
        r["userFraction"] = fraction
    if notes is not None:
        r["releaseNotes"] = [{"language": "ja-JP", "text": notes}]
    return r


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("cmd", choices=["status", "publish", "promote", "rollout", "next-code"])
    p.add_argument("args", nargs="*")
    p.add_argument("--fraction", type=float)
    p.add_argument("--complete", action="store_true")
    p.add_argument("--halt", action="store_true")
    p.add_argument("--notes")
    p.add_argument("--dry-run", action="store_true")
    a = p.parse_args()

    tok = token()
    edit = call(tok, "POST", "/edits", {})["id"]
    try:
        tracks = {t["track"]: t.get("releases", [])
                  for t in call(tok, "GET", f"/edits/{edit}/tracks").get("tracks", [])}

        if a.cmd == "next-code":
            # 上げ済みの全 bundle / apk と全トラックの最大 + 1。CI はこれでビルドする。
            # 実行番号から決めていた頃は、別経路で上がった番号とぶつかり、
            # アップロードが成功表示のまま Play に入らなかった（1.4.20 の 308）。
            codes = [int(b["versionCode"])
                     for b in call(tok, "GET", f"/edits/{edit}/bundles").get("bundles", [])]
            codes += [int(x["versionCode"])
                      for x in call(tok, "GET", f"/edits/{edit}/apks").get("apks", [])]
            codes += [int(c) for rels in tracks.values() for r in rels
                      for c in r.get("versionCodes", [])]
            print(max(codes, default=0) + 1)
            return

        if a.cmd == "status":
            for name, rels in tracks.items():
                print(f"[{name}]")
                for r in rels:
                    print(f"  {fmt(r)}")
            return

        if a.cmd == "publish":
            (track,) = a.args
            target = track
            new = apply_target(latest(tracks.get(track, []), "draft"), a.fraction, a.notes)
        elif a.cmd == "promote":
            src, target = a.args
            new = apply_target(latest(tracks.get(src, [])), a.fraction, a.notes)
        else:  # rollout
            (target,) = a.args
            cur = latest(tracks.get(target, []), "inProgress" if not a.halt else None)
            if a.halt:
                new = {**cur, "status": "halted"}
            else:
                if not a.complete and a.fraction is None:
                    sys.exit("--fraction か --complete か --halt を指定する")
                new = apply_target(cur, None if a.complete else a.fraction, a.notes)

        # 同じ versionCode の古いエントリ（draft 等）は置き換え、他の公開中リリースは残す
        keep = [r for r in tracks.get(target, [])
                if r["status"] in ("completed", "inProgress", "halted")
                and r.get("versionCodes") != new.get("versionCodes")]
        if new["status"] == "completed":
            keep = []  # completed は既存を置き換える
        body = {"track": target, "releases": keep + [new]}

        print(f"[{target}] -> {fmt(new)}")
        call(tok, "PUT", f"/edits/{edit}/tracks/{target}", body)
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
