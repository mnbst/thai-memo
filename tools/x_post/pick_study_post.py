"""X 投稿に使う Tips・ガイドの投稿文を1件選ぶ。

投稿文は study_posts.json に確認済みの完成文として置く（その場で書かせると
タイ語の誤りが混ざるため）。--kind で tip / guide を選び、その中から抽選する。

一巡するまで同じ文は出さない。投稿済みのキーを「study:<id>:<回数>」にして
posted.json に積み、出した回数が一番少ない文から抽選する。全部出し終えたら
回数がそろうので、自然に最初から繰り返しになる。

ガイドの文には、アプリのガイド画面の該当する欄を画像で付ける。描画は
test/screenshots/guide_screenshot.dart に任せ、ここでは <out>/guide_shot.env に
SCREEN と FROM を書くだけ。

出力は pick_sentence.py と同じく <out>/text.txt・key.txt・theme.txt。
実際に投稿できたかは post_to_x.py が確かめてから posted.json を更新する。
"""

from __future__ import annotations

import argparse
import json
import random
import re
import shlex
import sys
from pathlib import Path

from google.cloud import storage

from platforms import PLATFORMS, posted_object

POSTS_FILE = Path(__file__).with_name("study_posts.json")

# 履歴に残すテーマ名。例文のテーマと混ざらないようにする。
KIND_THEMES = {"tip": "Tips", "guide": "ガイド"}
GUIDE_SCREENS = ("script", "pron", "word_order", "tone")

# X の文字数の上限（重み付き）。日本語・タイ文字・絵文字は2、ASCII などは1。
TWEET_LIMIT = 280
_LIGHT = re.compile(
    "[\u0000-ჿ -‍‐-‟′-‷]"
)


def weighted_length(text: str) -> int:
    """X が数える文字数。URL は含めない前提。"""
    return sum(1 if _LIGHT.match(c) else 2 for c in text)


def build_text(post: dict) -> str:
    # ハッシュタグは付けない（例文の投稿と揃える）。
    return post["text"].rstrip()


def load_posts(kind: str | None = None) -> list[dict]:
    """投稿文を読み、壊れていたら止める。"""
    posts = json.loads(POSTS_FILE.read_text(encoding="utf-8"))
    errors = []
    ids = set()
    for post in posts:
        pid = post.get("id", "")
        if not pid or pid in ids:
            errors.append(f"id が空か重複: {pid!r}")
        ids.add(pid)
        if post.get("kind") not in KIND_THEMES:
            errors.append(f"{pid}: kind が不正")
        length = weighted_length(build_text(post))
        if length > TWEET_LIMIT:
            errors.append(f"{pid}: 長すぎる（{length}/{TWEET_LIMIT}）")
        image = post.get("image")
        if post.get("kind") == "guide" and not image:
            errors.append(f"{pid}: ガイドなのに画像の指定が無い")
        if image and (
            image.get("screen") not in GUIDE_SCREENS or not image.get("from")
        ):
            errors.append(f"{pid}: 画像の指定が不正")
        elif image and "," in image["from"]:
            # flutter の --dart-define はカンマで値を区切ってしまう。
            errors.append(f"{pid}: 画像の見出しにカンマは使えない")
    if errors:
        raise SystemExit("study_posts.json が不正:\n" + "\n".join(errors))
    return [p for p in posts if kind is None or p["kind"] == kind]


def times_posted(posted: list[str], pid: str) -> int:
    prefix = f"study:{pid}:"
    return sum(1 for key in posted if key.startswith(prefix))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project")
    parser.add_argument("--out", default="build/x_post")
    parser.add_argument("--kind", choices=sorted(KIND_THEMES))
    parser.add_argument("--seed", default="")
    # 一巡の数え方は投稿先ごと（Tips・ガイドは X と Threads で同じ文を出してよい）。
    parser.add_argument("--platform", choices=PLATFORMS, default="x")
    parser.add_argument(
        "--check",
        action="store_true",
        help="投稿文の検査だけして終わる（GCS には触らない）。",
    )
    args = parser.parse_args()

    if args.check:
        posts = load_posts()
        for kind in KIND_THEMES:
            print(f"{kind}: {sum(1 for p in posts if p['kind'] == kind)}件")
        return 0
    if not args.project or not args.kind:
        parser.error("--project と --kind が要る")

    posts = load_posts(args.kind)
    bucket = storage.Client(project=args.project).bucket(
        f"{args.project}-uvm-data"
    )
    blob = bucket.blob(posted_object(args.platform))
    state = json.loads(blob.download_as_bytes()) if blob.exists() else {}
    posted = state.get("posted", [])

    counts = {p["id"]: times_posted(posted, p["id"]) for p in posts}
    fewest = min(counts.values())
    candidates = [p for p in posts if counts[p["id"]] == fewest]
    picked = random.Random(args.seed or None).choice(candidates)
    print(
        f"{args.kind}: {picked['id']}（{fewest + 1}巡目、残り{len(candidates)}件）",
        file=sys.stderr,
    )

    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    (out / "text.txt").write_text(build_text(picked), encoding="utf-8")
    (out / "key.txt").write_text(
        f"study:{picked['id']}:{fewest}", encoding="utf-8"
    )
    (out / "theme.txt").write_text(KIND_THEMES[args.kind], encoding="utf-8")
    image = picked.get("image")
    if image:
        (out / "guide_shot.env").write_text(
            f"SCREEN={image['screen']}\nFROM={shlex.quote(image['from'])}\n",
            encoding="utf-8",
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
