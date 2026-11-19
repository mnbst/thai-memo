"""例文の縦動画を YouTube Shorts に出し、投稿済みを x_post/youtube/posted.json に記録する。

鍵は環境変数 YOUTUBE_UPLOAD（secret `youtube-upload` の JSON。issue_youtube_token.py が作る）。
縦（9:16）で3分以内の動画は Shorts として扱われる。タイトルに #Shorts も付ける。

  python tools/x_post/post_to_youtube.py --project thai-memo-prod --out build/x_post [--dry-run]

API の審査（YouTube API Services の監査）を通す前のプロジェクトから上げた動画は
非公開に固定される。審査が通るまでは YouTube Studio で手で公開にする。
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

import requests

TOKEN_URL = "https://oauth2.googleapis.com/token"
UPLOAD_URL = (
    "https://www.googleapis.com/upload/youtube/v3/videos"
    "?uploadType=resumable&part=snippet,status"
)
VIDEOS_URL = "https://www.googleapis.com/youtube/v3/videos"
APP_URL = "https://thai-memo-prod.web.app/app?c=youtube_shorts"
TITLE_LIMIT = 100
# YouTube の「教育」カテゴリ。
CATEGORY_EDUCATION = "27"
TAGS = ["タイ語", "タイ語勉強", "タイ語学習", "タイ語会話", "タイ旅行", "Shorts"]


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


def load_config() -> dict | None:
    raw = os.environ.get("YOUTUBE_UPLOAD", "")
    return json.loads(raw) if raw else None


def fetch_youtube_metrics(video_ids: list[str]) -> dict[str, dict]:
    """動画ごとの再生回数と反応の数を引く。引けなければ空（選定は止めない）。

    videos.list は1回 1 ユニット。50件までまとめて引ける。
    """
    config = load_config()
    if not video_ids or not config:
        return {}
    try:
        token = access_token(config)
        response = requests.get(
            VIDEOS_URL,
            headers={"Authorization": f"Bearer {token}"},
            params={"part": "statistics", "id": ",".join(video_ids[:50])},
            timeout=30,
        )
        response.raise_for_status()
    except requests.RequestException as error:
        print(f"反応の取得を諦める: {error}", file=sys.stderr)
        return {}
    result = {}
    for item in response.json().get("items", []):
        stats = item.get("statistics", {})
        # X・Threads と同じく、表示回数（ここでは再生回数）と反応の和を持つ。
        result[item["id"]] = {
            "impressions": int(stats.get("viewCount", 0)),
            "score": int(stats.get("likeCount", 0))
            + int(stats.get("commentCount", 0)),
        }
    return result


def build_title(text: str, thai: str) -> str:
    """「書き出し｜タイ語 #Shorts」。長ければタイ語を落とし、書き出しだけにする。"""
    first = text.splitlines()[0] if text else ""
    # 書き出しが無い本文は1行目からタイ語になる。
    hook = first.rstrip("👇").strip() if first.endswith("👇") else ""
    tail = " #タイ語 #Shorts"
    candidates = [f"{hook}｜{thai}", hook] if hook else [thai]
    for head in candidates:
        if head and len(head + tail) <= TITLE_LIMIT:
            return head + tail
    return f"今日のタイ語{tail}"


def build_description(text: str) -> str:
    """X と同じ本文（タイ語・読み・訳）のあとにアプリの案内を足す。"""
    lines = text.splitlines()
    # 1行目の書き出しはタイトルに入れたので、本文からは外す。
    if lines and lines[0].endswith("👇"):
        lines = lines[1:]
    body = "\n".join(lines).strip()
    return "\n".join(
        [
            body,
            "",
            "📱 毎日1文、タイ語の例文が届くアプリ「まいにちタイ語」",
            "単語分解・発音採点・クイズで、タイ文字が読めなくても始められます。",
            APP_URL,
            "",
            "#タイ語 #タイ語勉強 #タイ語学習 #Shorts",
        ]
    )


def upload(token: str, video: Path, title: str, description: str) -> str:
    """resumable で動画を上げ、動画 ID を返す。"""
    metadata = {
        "snippet": {
            "title": title,
            "description": description,
            "tags": TAGS,
            "categoryId": CATEGORY_EDUCATION,
            "defaultLanguage": "ja",
            "defaultAudioLanguage": "th",
        },
        "status": {
            "privacyStatus": "public",
            "selfDeclaredMadeForKids": False,
        },
    }
    start = requests.post(
        UPLOAD_URL,
        headers={
            "Authorization": f"Bearer {token}",
            "X-Upload-Content-Type": "video/mp4",
            "Content-Type": "application/json; charset=UTF-8",
        },
        data=json.dumps(metadata, ensure_ascii=False).encode(),
        timeout=30,
    )
    start.raise_for_status()
    response = requests.put(
        start.headers["Location"],
        headers={"Content-Type": "video/mp4"},
        data=video.read_bytes(),
        timeout=600,
    )
    response.raise_for_status()
    return response.json()["id"]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", required=True)
    parser.add_argument("--out", default="build/x_post")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    out = Path(args.out)
    text = (out / "text.txt").read_text(encoding="utf-8")
    key = (out / "key.txt").read_text(encoding="utf-8").strip()
    sentence = json.loads((out / "sentence.json").read_text(encoding="utf-8"))
    video = out / "post.mp4"
    if not video.exists():
        print("post.mp4 が無いので出さない", file=sys.stderr)
        return 1

    title = build_title(text, sentence.get("thai_text", ""))
    description = build_description(text)
    if args.dry_run:
        print(f"--- title\n{title}\n--- description\n{description}")
        return 0

    config = load_config()
    if not config:
        print("YOUTUBE_UPLOAD が無いので出さない", file=sys.stderr)
        return 1
    video_id = upload(access_token(config), video, title, description)
    print(f"YouTube に出した: https://youtube.com/shorts/{video_id}")

    # tweepy 等を読むので、記録するときだけ取り込む。
    from post_to_x import record_post

    record_post(args.project, out, key, text, {"post_id": video_id},
                platform="youtube", lang="ja")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
