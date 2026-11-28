"""X 投稿に使う Tips・ガイドの投稿文を1件選ぶ。

投稿文は study_posts.json に確認済みの完成文として置く（その場で書かせると
タイ語の誤りが混ざるため）。--kind で tip / guide / feature を選び、その中から抽選する。

一巡するまで同じ文は出さない。投稿済みのキーを「study:<id>:<巡目>」にして
posted.json に積み、巡目が一番若い文から抽選する。全部出し終えたら
巡目がそろうので、自然に最初から繰り返しになる。新しく足した文は今の巡に
入れ、その巡の残りを出し終えてから最後に出す（足した直後に割り込ませない）。

ガイドの文には、アプリのガイド画面の該当する欄を画像で付ける。描画は
test/screenshots/guide_screenshot.dart に任せ、ここでは <out>/guide_shot.env に
SCREEN と FROM を書くだけ。機能紹介（feature）の文には、image_file に書いた
固定の画像（ストア用スクショ）を <out>/image_1.png に置く。

出力は pick_sentence.py と同じく <out>/text.txt・key.txt・theme.txt。TikTok 用に
英語の文を <out>/text_en.txt に書く。--platform tiktok は英語の文がある投稿だけから選び、
一巡は x_post/en/tiktok/posted.json で数える。
実際に投稿できたかは post_to_x.py が確かめてから posted.json を更新する。
"""

from __future__ import annotations

import argparse
import json
import random
import re
import shlex
import shutil
import sys
from pathlib import Path

from google.cloud import storage

from platforms import PLATFORMS, posted_object

POSTS_FILE = Path(__file__).with_name("study_posts.json")

# 履歴に残すテーマ名。例文のテーマと混ざらないようにする。
KIND_THEMES = {"tip": "Tips", "guide": "ガイド", "feature": "機能紹介"}
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
        elif image and "," in image["from"] + image.get("expand", ""):
            # flutter の --dart-define はカンマで値を区切ってしまう。
            errors.append(f"{pid}: 画像の見出しにカンマは使えない")
        if post.get("kind") in ("tip", "guide") and not post.get("text_en"):
            errors.append(f"{pid}: 英語版（text_en）が無い")
        image_file = post.get("image_file")
        if post.get("kind") == "feature" and not image_file:
            errors.append(f"{pid}: 機能紹介なのに image_file が無い")
        if image_file and not (POSTS_FILE.parent / image_file).is_file():
            errors.append(f"{pid}: image_file が見つからない: {image_file}")
    if errors:
        raise SystemExit("study_posts.json が不正:\n" + "\n".join(errors))
    return [p for p in posts if kind is None or p["kind"] == kind]


def rounds_done(posted: list[str], pid: str) -> int:
    """出し終えた巡の数（記録の巡目の最大＋1）。途中から足した文は巡目が飛ぶので数では数えない。"""
    prefix = f"study:{pid}:"
    rounds = [
        int(key[len(prefix):]) for key in posted
        if key.startswith(prefix) and key[len(prefix):].isdigit()
    ]
    return max(rounds) + 1 if rounds else 0


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
    # TikTok は英語だけなので、英語の文がある投稿から選ぶ。記録も英語（x_post/en/tiktok/）。
    lang = "ja"
    if args.platform == "tiktok":
        posts = [p for p in posts if p.get("text_en")]
        lang = "en"
        if not posts:
            print(f"{args.kind}: 英語の文が無い", file=sys.stderr)
            return 1
    bucket = storage.Client(project=args.project).bucket(
        f"{args.project}-uvm-data"
    )
    blob = bucket.blob(posted_object(args.platform, lang))
    state = json.loads(blob.download_as_bytes()) if blob.exists() else {}
    posted = state.get("posted", [])

    done = {p["id"]: rounds_done(posted, p["id"]) for p in posts}
    # 今の巡は、一番進んだ文が出し終えた巡。全部そろっていれば次の巡を始める。
    most = max(done.values())
    behind = [p for p in posts if done[p["id"]] < most]
    if behind:
        fewest = most - 1
        # 今の巡の残りを先に出し、途中から足した文（それより遅れている文）は最後に出す。
        candidates = [p for p in behind if done[p["id"]] == fewest] or behind
    else:
        fewest = most
        candidates = posts
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
    # TikTok 用の英語版（画像・説明文）。英語の文がある Tips・ガイドだけ。
    if picked.get("text_en"):
        (out / "text_en.txt").write_text(picked["text_en"].rstrip(), encoding="utf-8")
    image_file = picked.get("image_file")
    if image_file:
        shutil.copyfile(POSTS_FILE.parent / image_file, out / "image_1.png")
    image = picked.get("image")
    if image:
        (out / "guide_shot.env").write_text(
            f"SCREEN={image['screen']}\nFROM={shlex.quote(image['from'])}\n"
            f"EXPAND={shlex.quote(image.get('expand', ''))}\n",
            encoding="utf-8",
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
