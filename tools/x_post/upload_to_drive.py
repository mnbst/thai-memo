"""投稿素材（TikTok 用の動画・画像と説明文）を Google Drive のフォルダに置く。

鍵は環境変数 GOOGLE_DRIVE_UPLOAD（secret `google-drive-upload` の JSON。
issue_drive_token.py が作る）。ファイル名の頭に日付と枠を付け、並べたときに
投稿順になるようにする。

  python tools/x_post/upload_to_drive.py --prefix 2026-11-16_0700_ja \\
    build/x_post/post.mp4 build/x_post/text.txt

--record <dir> を付けると、全部置けたときに <dir> の例文を TikTok の投稿済みとして
記録する（pick_sentence.py --platform tiktok で選んだ文。次から同じ文を選ばない）。

置けなくても投稿（X）は止めない。失敗は終了コード 1 で知らせる。
"""

from __future__ import annotations

import argparse
import json
import mimetypes
import os
import sys
from pathlib import Path

import requests

TOKEN_URL = "https://oauth2.googleapis.com/token"
UPLOAD_URL = "https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable"


def access_token(config: dict) -> str:
    response = requests.post(
        TOKEN_URL,
        data={
            "client_id": config["client_id"],
            "client_secret": config["client_secret"],
            "refresh_token": config["refresh_token"],
            "grant_type": "refresh_token",
        },
        timeout=30,
    )
    response.raise_for_status()
    return response.json()["access_token"]


def upload(token: str, folder_id: str, path: Path, name: str) -> str:
    """resumable で1ファイル送る（動画が数 MB あるので multipart にしない）。"""
    mime = mimetypes.guess_type(path.name)[0] or "application/octet-stream"
    start = requests.post(
        UPLOAD_URL,
        headers={
            "Authorization": f"Bearer {token}",
            "X-Upload-Content-Type": mime,
        },
        json={"name": name, "parents": [folder_id]},
        timeout=30,
    )
    start.raise_for_status()
    response = requests.put(
        start.headers["Location"],
        headers={"Content-Type": mime},
        data=path.read_bytes(),
        timeout=300,
    )
    response.raise_for_status()
    return response.json()["id"]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--prefix", required=True, help="ファイル名の頭（日付_枠_言語など）")
    parser.add_argument("files", nargs="+", type=Path)
    parser.add_argument("--record", type=Path, help="TikTok の投稿済みに記録する例文の置き場")
    parser.add_argument("--project", default="", help="--record の記録先の GCP プロジェクト")
    parser.add_argument("--lang", default="ja", help="--record の言語")
    args = parser.parse_args()

    raw = os.environ.get("GOOGLE_DRIVE_UPLOAD", "")
    if not raw:
        print("GOOGLE_DRIVE_UPLOAD が無いので Drive には置かない", file=sys.stderr)
        return 1
    config = json.loads(raw)
    token = access_token(config)

    failed = False
    names = []
    for path in args.files:
        if not path.exists():
            print(f"無いので飛ばす: {path}", file=sys.stderr)
            continue
        name = f"{args.prefix}_{path.name}"
        try:
            upload(token, config["folder_id"], path, name)
            names.append(name)
            print(f"Drive に置いた: {name}")
        except requests.RequestException as e:
            failed = True
            print(f"Drive に置けなかった: {name}（{e}）", file=sys.stderr)
    if args.record and names and not failed:
        # tweepy 等を読むので、記録するときだけ取り込む。
        from post_to_x import record_post

        key = (args.record / "key.txt").read_text(encoding="utf-8").strip()
        text = (args.record / "text.txt").read_text(encoding="utf-8")
        record_post(args.project, args.record, key, text,
                    {"drive_name": names[0]}, platform="tiktok", lang=args.lang)
        print(f"TikTok の投稿済みに記録した: {key}")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
