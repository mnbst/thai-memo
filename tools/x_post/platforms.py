"""投稿先（X / Threads）と言語（アカウント）ごとの記録の置き場所。

同じ枠の時刻に両方へ出すが、例文は別の文にする。記録は投稿先ごとに分け、
例文を選ぶときだけ同じ言語の両方の投稿済みを外す（pick_sentence.py）。
言語ごとにアカウントが別（ja: @everydaythai775 / en: @daily_thai11）なので、
記録も言語で分ける。ja は言語を分ける前からの置き場所のまま。
"""

from __future__ import annotations

PLATFORMS = ("x", "threads")
# 投稿する言語（訳と画面の言語）。ko はアカウントができたら足す。
LANGS = ("ja", "en")

# 投稿済みと履歴。X 投稿用 SA が書けるのは x_post/ の下だけなので Threads もその下に置く。
POSTED_OBJECTS = {
    "x": "x_post/posted.json",
    "threads": "x_post/threads/posted.json",
}


def posted_object(platform: str, lang: str = "ja") -> str:
    name = POSTED_OBJECTS[platform]
    if lang == "ja":
        return name
    return name.replace("x_post/", f"x_post/{lang}/", 1)


def post_id(entry: dict) -> str | None:
    """履歴1件の投稿 ID。X は tweet_id、Threads は post_id に持つ。"""
    return entry.get("tweet_id") or entry.get("post_id")
