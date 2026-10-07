"""prod 通知コーチング再案内A/Bの集計。

1.4.17 から、コーチングを断った人への再案内を uid のハッシュで半分にだけ出す
（show / holdout）。対象になった人は users/{uid}.notif_reprompt_experiment に
{id, arm, assigned_at} が残るので、群ごとに次を比べる。

  - 通知トークン取得率（fcm_token あり）
  - 割り当てから N 日以上経った人のうち、N 日後以降もアプリを開いた割合

群の割り当ては lib/presentation/widgets/notification_coach_dialog.dart の
assignNotificationRepromptArm と同じ計算（arm()）。記録との食い違いも数える。

usage:
  python3 scripts/notif_reprompt_experiment.py [experiment_id]
  # 既定 notif_reprompt_1.4.17。gcloud auth（prod の Firestore 読み取り権限）が必要。
"""

import json
import subprocess
import sys
from datetime import datetime, timezone

PROJECT = "thai-memo-prod"
DEFAULT_EXPERIMENT = "notif_reprompt_1.4.17"
DAYS = (1, 3, 7, 14)


def arm(uid: str, experiment_id: str) -> str:
    """FNV-1a 32bit の偶奇で群を決める（Dart 側と同じ）。"""
    h = 0x811C9DC5
    for b in f"{uid}:{experiment_id}".encode():
        h ^= b
        h = (h * 0x01000193) & 0xFFFFFFFF
    return "show" if h % 2 == 0 else "holdout"


def token() -> str:
    return subprocess.run(
        ["gcloud", "auth", "print-access-token"],
        capture_output=True, text=True, check=True,
    ).stdout.strip()


def fetch_users(access_token: str) -> list[dict]:
    base = (
        f"https://firestore.googleapis.com/v1/projects/{PROJECT}"
        "/databases/(default)/documents/users"
    )
    fields = ["notif_reprompt_experiment", "fcm_token", "last_opened_at", "last_active_at"]
    mask = "&".join(f"mask.fieldPaths={f}" for f in fields)
    docs, page = [], ""
    while True:
        url = f"{base}?pageSize=300&{mask}" + (f"&pageToken={page}" if page else "")
        out = subprocess.run(
            ["curl", "-s", "-H", f"Authorization: Bearer {access_token}", url],
            capture_output=True, text=True, check=True,
        ).stdout
        data = json.loads(out)
        if "error" in data:
            raise SystemExit(data["error"])
        docs += data.get("documents", [])
        page = data.get("nextPageToken", "")
        if not page:
            return docs


def ts(value: dict | None) -> datetime | None:
    if not value or "timestampValue" not in value:
        return None
    return datetime.fromisoformat(value["timestampValue"].replace("Z", "+00:00"))


def main() -> None:
    experiment_id = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_EXPERIMENT
    now = datetime.now(timezone.utc)
    groups: dict[str, list[dict]] = {"show": [], "holdout": []}
    mismatch = 0

    for doc in fetch_users(token()):
        f = doc.get("fields", {})
        exp = f.get("notif_reprompt_experiment", {}).get("mapValue", {}).get("fields", {})
        if exp.get("id", {}).get("stringValue") != experiment_id:
            continue
        uid = doc["name"].rsplit("/", 1)[1]
        recorded = exp.get("arm", {}).get("stringValue")
        if recorded != arm(uid, experiment_id):
            mismatch += 1
        assigned = ts(exp.get("assigned_at"))
        if assigned is None or recorded not in groups:
            continue
        seen = [t for t in (ts(f.get("last_opened_at")), ts(f.get("last_active_at"))) if t]
        groups[recorded].append({
            "token": "fcm_token" in f,
            "elapsed": (now - assigned).days,
            "returned_after": (max(seen) - assigned).days if seen else -1,
        })

    print(f"experiment: {experiment_id}  (群の記録と計算の食い違い: {mismatch})")
    for name, rows in groups.items():
        n = len(rows)
        if not n:
            print(f"{name:8s} n=0")
            continue
        tok = sum(r["token"] for r in rows)
        cols = []
        for d in DAYS:
            eligible = [r for r in rows if r["elapsed"] >= d]
            kept = sum(r["returned_after"] >= d for r in eligible)
            cols.append(f"D{d}+ {kept}/{len(eligible)}" + (
                f"({100 * kept // len(eligible)}%)" if eligible else ""))
        print(f"{name:8s} n={n:3d}  トークン {tok}({100 * tok // n}%)  " + "  ".join(cols))


if __name__ == "__main__":
    main()
