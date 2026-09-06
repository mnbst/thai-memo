"""X へ投稿し、投稿済みの記録を GCS に書き戻す。

動画（カード画像＋読み上げ）を優先し、動画のアップロードに失敗したら画像に、
画像も駄目ならテキストだけに落とす。読み上げが載らなくても、その日の投稿は
出す方を選ぶ。

認証は OAuth 1.0a のユーザーコンテキスト。鍵は環境変数で渡す:
  X_API_KEY / X_API_SECRET / X_ACCESS_TOKEN / X_ACCESS_TOKEN_SECRET
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path

import tweepy
from google.cloud import storage

POSTED_OBJECT = "x_post/posted.json"
# 投稿済みキーの保持数。バンクの規模より十分大きければ一巡を検知できる。
POSTED_LIMIT = 5000
# 反応の参照に使う履歴の保持数。直近10日ぶんあれば足りるが余裕を持たせる。
HISTORY_LIMIT = 60


def credentials() -> dict[str, str]:
    keys = ["X_API_KEY", "X_API_SECRET", "X_ACCESS_TOKEN", "X_ACCESS_TOKEN_SECRET"]
    missing = [k for k in keys if not os.environ.get(k)]
    if missing:
        raise SystemExit(f"環境変数が足りない: {', '.join(missing)}")
    return {k: os.environ[k] for k in keys}


def upload_media(api: tweepy.API, out: Path) -> list[str]:
    """動画を優先し、駄目なら画像。どちらも駄目なら空を返す。"""
    video = out / "post.mp4"
    if video.exists():
        try:
            media = api.chunked_upload(
                filename=str(video),
                file_type="video/mp4",
                media_category="tweet_video",
                wait_for_async_finalize=True,
            )
            return [media.media_id_string]
        except Exception as error:  # noqa: BLE001 - 落とさず画像へ退避する
            print(f"動画のアップロードに失敗、画像で投稿する: {error}", file=sys.stderr)

    ids = []
    for path in sorted(out.glob("image_*.png")):
        try:
            ids.append(api.media_upload(filename=str(path)).media_id_string)
        except Exception as error:  # noqa: BLE001
            print(f"画像のアップロードに失敗: {path.name}: {error}", file=sys.stderr)
    return ids


def mark_posted(project: str, key: str, entry: dict) -> None:
    """投稿済みキーと、後で反応を引くための履歴を書き戻す。

    履歴は pick_sentence.py が「伸びた投稿に近いもの」を選ぶのに使う。
    tweet_id が無いと反応を引けないので、投稿が通ってから呼ぶこと。
    """
    bucket = storage.Client(project=project).bucket(f"{project}-uvm-data")
    blob = bucket.blob(POSTED_OBJECT)
    state = json.loads(blob.download_as_bytes()) if blob.exists() else {}

    posted = [k for k in state.get("posted", []) if k != key]
    posted.append(key)

    history = [h for h in state.get("history", []) if h.get("key") != key]
    history.append(entry)

    blob.upload_from_string(
        json.dumps(
            {
                "posted": posted[-POSTED_LIMIT:],
                "history": history[-HISTORY_LIMIT:],
            },
            ensure_ascii=False,
        ),
        content_type="application/json",
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", required=True)
    parser.add_argument("--out", default="build/x_post")
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="投稿はせず、本文と添付するメディアだけ出す。",
    )
    args = parser.parse_args()

    out = Path(args.out)
    text = (out / "text.txt").read_text(encoding="utf-8")
    key = (out / "key.txt").read_text(encoding="utf-8").strip()

    if args.dry_run:
        media = [p.name for p in sorted(out.glob("image_*.png"))]
        if (out / "post.mp4").exists():
            media = ["post.mp4"]
        print(text)
        print(f"--- media: {', '.join(media) or 'なし'}")
        return 0

    creds = credentials()
    auth = tweepy.OAuth1UserHandler(
        creds["X_API_KEY"],
        creds["X_API_SECRET"],
        creds["X_ACCESS_TOKEN"],
        creds["X_ACCESS_TOKEN_SECRET"],
    )
    api = tweepy.API(auth)
    client = tweepy.Client(
        consumer_key=creds["X_API_KEY"],
        consumer_secret=creds["X_API_SECRET"],
        access_token=creds["X_ACCESS_TOKEN"],
        access_token_secret=creds["X_ACCESS_TOKEN_SECRET"],
    )

    media_ids = upload_media(api, out)
    response = client.create_tweet(text=text, media_ids=media_ids or None)

    tweet_id = response.data["id"]
    print(f"投稿した: https://x.com/i/status/{tweet_id}")

    sentence = json.loads((out / "sentence.json").read_text(encoding="utf-8"))
    mark_posted(
        args.project,
        key,
        {
            "key": key,
            "tweet_id": str(tweet_id),
            "thai_text": sentence.get("thai_text", ""),
            "japanese_translation": sentence.get("japanese_translation", ""),
            "posted_at": datetime.now(timezone.utc).isoformat(),
        },
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
