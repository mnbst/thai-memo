"""X 投稿に使う例文を1件選ぶ。

例文は GCS の free 例文バンク（gs://<project>-uvm-data/free_sentences_ja.json）
から取る。毎日配信の例文はユーザーごとに生成される個人データなので、そのまま
公開投稿には使わない。バンクは同じ生成パイプラインで作った共有プール。

投稿済みは gs://<project>-uvm-data/x_post/posted.json で管理する。
選んだ例文は <out>/sentence.json、投稿本文は <out>/text.txt に書く。
実際に投稿できたかは post_to_x.py が確かめてから posted.json を更新する。
"""

from __future__ import annotations

import argparse
import hashlib
import json
import random
import sys
from datetime import datetime, timezone
from pathlib import Path

from google.cloud import storage

BANK_OBJECT = "free_sentences_ja.json"
POSTED_OBJECT = "x_post/posted.json"


def sentence_key(sentence: dict) -> str:
    """例文の同一性はタイ語本文で見る。バンクを作り直してもぶれない。"""
    return hashlib.sha1(sentence["thai_text"].encode("utf-8")).hexdigest()


def load_json(bucket: storage.Bucket, name: str, fallback):
    blob = bucket.blob(name)
    if not blob.exists():
        return fallback
    return json.loads(blob.download_as_bytes())


def build_text(sentence: dict) -> str:
    """投稿本文。手で出していた形をそのまま踏襲する。"""
    lines = ["今日のタイ語", ""]
    lines.append(sentence["thai_text"])
    if sentence.get("pronunciation"):
        lines.append(sentence["pronunciation"])
    lines += ["", sentence["japanese_translation"]]
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", required=True)
    parser.add_argument("--out", default="build/x_post")
    parser.add_argument(
        "--seed",
        default="",
        help="抽選の種。日付を渡すと同じ日は同じ例文になる。",
    )
    args = parser.parse_args()

    bucket = storage.Client(project=args.project).bucket(
        f"{args.project}-uvm-data"
    )

    bank = load_json(bucket, BANK_OBJECT, [])
    if not bank:
        print(f"例文バンクが空: gs://{bucket.name}/{BANK_OBJECT}", file=sys.stderr)
        return 1

    posted = set(load_json(bucket, POSTED_OBJECT, {}).get("posted", []))
    candidates = [s for s in bank if sentence_key(s) not in posted]
    if not candidates:
        # 一巡したら投稿済みを無視して最初から回す。止まるよりは繰り返す。
        print("未投稿の例文が尽きたのでバンク全体から選ぶ", file=sys.stderr)
        candidates = bank

    picked = random.Random(args.seed or None).choice(candidates)
    # 詳細画面は作成日を出す。投稿日を入れて「不明」を出さない。
    picked.setdefault(
        "created_at", datetime.now(timezone.utc).astimezone().isoformat()
    )

    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    (out / "sentence.json").write_text(
        json.dumps(picked, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    (out / "text.txt").write_text(build_text(picked), encoding="utf-8")
    (out / "key.txt").write_text(sentence_key(picked), encoding="utf-8")

    print(picked["thai_text"])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
