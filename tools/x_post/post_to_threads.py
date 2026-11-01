"""Threads へ投稿し、投稿済みの記録を GCS に書き戻す。

中身は X と同じ作り（pick_sentence.py / pick_study_post.py の出力）を受ける。
添付は動画1本と画像をカルーセルで。Threads はメディアを URL で取りに来るので、
GCS に置いて期限付き URL（署名付き）を渡し、投稿が済んだら消す。
拒まれたら 動画＋画像 → 動画だけ → 画像だけ → テキストだけ、と落としていく。

認証は Threads の長期アクセストークン（60日）。環境変数 THREADS_ACCESS_TOKEN で渡す。
--token-secret を渡すと、Secret Manager の最新版が古くなったときにトークンを
延長して新しい版を足す（期限切れで止まらないように）。
"""

from __future__ import annotations

import argparse
import os
import sys
import time
import uuid
from datetime import datetime, timedelta, timezone
from pathlib import Path

import google.auth
import google.auth.transport.requests
import requests
from google.cloud import secretmanager, storage

from post_to_x import record_post

API = "https://graph.threads.net/v1.0"
# 本文の上限。X（重み付き280）に収めた本文なので普段は届かない。
TEXT_LIMIT = 500
# カルーセルは20件まで。X と揃えて動画1本＋画像3枚にする。
IMAGE_LIMIT = 3
MEDIA_PREFIX = "x_post/threads/media"
# Threads がメディアを取りに来るまでの猶予。処理の待ちより十分長くする。
URL_TTL = timedelta(hours=2)
# コンテナの処理待ち。動画は数十秒かかることがある。
POLL_SECONDS = 5
POLL_LIMIT = 60
# トークンの延長。発行から24時間たたないと延長できず、60日で切れる。
REFRESH_AFTER = timedelta(days=7)


class ThreadsError(Exception):
    pass


def call(method: str, path: str, token: str, **params) -> dict:
    response = requests.request(
        method,
        f"{API}/{path}",
        params={**params, "access_token": token},
        timeout=60,
    )
    if response.status_code != 200:
        raise ThreadsError(f"{response.status_code} {response.text[:300]}")
    return response.json()


def wait_ready(container_id: str, token: str) -> None:
    """コンテナがメディアを取り込み終えるまで待つ。"""
    for _ in range(POLL_LIMIT):
        info = call("GET", container_id, token, fields="status,error_message")
        status = info.get("status")
        if status == "FINISHED":
            return
        if status in ("ERROR", "EXPIRED"):
            raise ThreadsError(f"{status}: {info.get('error_message', '')}")
        time.sleep(POLL_SECONDS)
    raise ThreadsError("メディアの取り込みが終わらない")


def item(kind: str, url: str, token: str) -> str:
    """カルーセルの1件を作る。"""
    field = "video_url" if kind == "VIDEO" else "image_url"
    container = call(
        "POST",
        "me/threads",
        token,
        media_type=kind,
        is_carousel_item="true",
        **{field: url},
    )["id"]
    wait_ready(container, token)
    return container


def create_post(text: str, media: list[tuple[str, str]], token: str) -> str:
    """media（(種類, URL) の並び）を付けた投稿を作って公開し、投稿 ID を返す。"""
    if len(media) >= 2:
        children = [item(kind, url, token) for kind, url in media]
        container = call(
            "POST",
            "me/threads",
            token,
            media_type="CAROUSEL",
            children=",".join(children),
            text=text,
        )["id"]
    elif media:
        kind, url = media[0]
        field = "video_url" if kind == "VIDEO" else "image_url"
        container = call(
            "POST", "me/threads", token, media_type=kind, text=text, **{field: url}
        )["id"]
    else:
        container = call("POST", "me/threads", token, media_type="TEXT", text=text)[
            "id"
        ]
    wait_ready(container, token)
    return call("POST", "me/threads_publish", token, creation_id=container)["id"]


def media_candidates(
    video: tuple[str, str] | None, images: list[tuple[str, str]]
) -> list[list[tuple[str, str]]]:
    """添付の組み合わせを、望ましい順に並べて返す（post_to_x.py と同じ落とし方）。"""
    sets = []
    if video and images:
        sets.append([video, *images])
    if video:
        sets.append([video])
    if images:
        sets.append(images)
    sets.append([])
    return sets


def signer() -> tuple[str, str]:
    """署名付き URL を作る SA と、そのアクセストークン。

    鍵ファイルは使わず、IAM の signBlob で署名する（SA に自分への
    serviceAccountTokenCreator が要る）。
    """
    credentials, _ = google.auth.default(
        scopes=["https://www.googleapis.com/auth/cloud-platform"]
    )
    credentials.refresh(google.auth.transport.requests.Request())
    email = os.environ.get("THREADS_SIGNER") or getattr(
        credentials, "service_account_email", None
    )
    if not email:
        raise SystemExit("署名に使う SA が分からない（THREADS_SIGNER を渡す）")
    return email, credentials.token


def upload_media(
    bucket: storage.Bucket, out: Path
) -> tuple[list[storage.Blob], tuple[str, str] | None, list[tuple[str, str]]]:
    """動画と画像を GCS に置き、Threads が取りに来る URL を返す。"""
    email, access_token = signer()
    prefix = f"{MEDIA_PREFIX}/{uuid.uuid4().hex}"
    blobs = []

    def put(path: Path, content_type: str) -> str:
        blob = bucket.blob(f"{prefix}/{path.name}")
        blob.upload_from_filename(str(path), content_type=content_type)
        blobs.append(blob)
        return blob.generate_signed_url(
            version="v4",
            expiration=URL_TTL,
            method="GET",
            service_account_email=email,
            access_token=access_token,
        )

    video = None
    if (out / "post.mp4").exists():
        video = ("VIDEO", put(out / "post.mp4", "video/mp4"))
    images = [
        ("IMAGE", put(path, "image/png"))
        for path in sorted(out.glob("image_*.png"))[:IMAGE_LIMIT]
    ]
    return blobs, video, images


def refresh_token(secret: str, token: str) -> None:
    """Secret Manager の最新版が古ければ、トークンを延長して新しい版を足す。

    失敗しても投稿は止めない（期限までまだ日がある）。
    """
    client = secretmanager.SecretManagerServiceClient()
    latest = client.get_secret_version(name=f"{secret}/versions/latest")
    age = datetime.now(timezone.utc) - latest.create_time
    if age < REFRESH_AFTER:
        return
    response = requests.get(
        "https://graph.threads.net/refresh_access_token",
        params={"grant_type": "th_refresh_token", "access_token": token},
        timeout=30,
    )
    if response.status_code != 200:
        print(
            f"トークンを延長できない: {response.status_code} {response.text[:200]}",
            file=sys.stderr,
        )
        return
    client.add_secret_version(
        parent=secret,
        payload={"data": response.json()["access_token"].encode()},
    )
    # 古い版は無効にする（最新の1つ前は念のため残す）。
    for version in list(client.list_secret_versions(parent=secret))[2:]:
        if version.state == secretmanager.SecretVersion.State.ENABLED:
            client.disable_secret_version(name=version.name)
    print(f"トークンを延長した（前の版から{age.days}日）", file=sys.stderr)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", required=True)
    parser.add_argument("--out", default="build/x_post")
    parser.add_argument(
        "--token-secret",
        default="",
        help="トークンの secret（projects/<p>/secrets/<name>）。古ければ延長する。",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="投稿はせず、本文と添付するメディアだけ出す。",
    )
    args = parser.parse_args()

    out = Path(args.out)
    text = (out / "text.txt").read_text(encoding="utf-8")
    key = (out / "key.txt").read_text(encoding="utf-8").strip()
    if len(text) > TEXT_LIMIT:
        raise SystemExit(f"本文が長すぎる（{len(text)}/{TEXT_LIMIT}）")

    if args.dry_run:
        media = [p.name for p in sorted(out.glob("image_*.png"))[:IMAGE_LIMIT]]
        if (out / "post.mp4").exists():
            media = ["post.mp4", *media]
        print(text)
        print(f"--- media: {', '.join(media) or 'なし'}")
        return 0

    token = os.environ.get("THREADS_ACCESS_TOKEN")
    if not token:
        raise SystemExit("環境変数が足りない: THREADS_ACCESS_TOKEN")

    bucket = storage.Client(project=args.project).bucket(
        f"{args.project}-uvm-data"
    )
    blobs, video, images = [], None, []
    try:
        blobs, video, images = upload_media(bucket, out)
    except Exception as error:  # noqa: BLE001 - 添付なしでも出す
        print(f"メディアを置けない: {error}", file=sys.stderr)

    post_id = None
    try:
        for media in media_candidates(video, images):
            try:
                post_id = create_post(text, media, token)
                break
            except ThreadsError as error:
                print(
                    f"添付{len(media)}件で投稿できず、減らして試す: {error}",
                    file=sys.stderr,
                )
    finally:
        for blob in blobs:
            try:
                blob.delete()
            except Exception as error:  # noqa: BLE001
                print(f"メディアを消せない: {blob.name}: {error}", file=sys.stderr)
    if post_id is None:
        raise SystemExit("投稿できなかった")

    try:
        link = call("GET", post_id, token, fields="permalink").get("permalink")
    except ThreadsError:
        link = post_id
    print(f"投稿した: {link}")

    record_post(args.project, out, key, text, {"post_id": str(post_id)}, "threads")

    if args.token_secret:
        try:
            refresh_token(args.token_secret, token)
        except Exception as error:  # noqa: BLE001 - 投稿は済んでいる
            print(f"トークンの延長に失敗: {error}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
