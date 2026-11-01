"""投稿先（X / Threads）ごとの記録の置き場所。

同じ枠の時刻に両方へ出すが、例文は別の文にする。記録は投稿先ごとに分け、
例文を選ぶときだけ両方の投稿済みを外す（pick_sentence.py）。
"""

from __future__ import annotations

PLATFORMS = ("x", "threads")

# 投稿済みと履歴。X 投稿用 SA が書けるのは x_post/ の下だけなので Threads もその下に置く。
POSTED_OBJECTS = {
    "x": "x_post/posted.json",
    "threads": "x_post/threads/posted.json",
}


def posted_object(platform: str) -> str:
    return POSTED_OBJECTS[platform]


def post_id(entry: dict) -> str | None:
    """履歴1件の投稿 ID。X は tweet_id、Threads は post_id に持つ。"""
    return entry.get("tweet_id") or entry.get("post_id")
