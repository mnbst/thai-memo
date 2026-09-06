"""X 投稿に使う例文を1件選ぶ。

前日に生成された例文（Firestore の collection group `sentences`）を候補にして、
その中から「反応が良さそうな1件」を Gemini に選ばせる。前日分が取れないときや
Gemini が使えないときは、GCS の free 例文バンクに落として投稿を止めない。

投稿済みは gs://<project>-uvm-data/x_post/posted.json で管理する。
選んだ例文は <out>/sentence.json、投稿本文は <out>/text.txt に書く。
実際に投稿できたかは post_to_x.py が確かめてから posted.json を更新する。
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import random
import re
import ssl
import sys
import urllib.error
import urllib.request
from datetime import datetime, timedelta, timezone
from pathlib import Path

import certifi
import requests
from google.api_core import exceptions as gcp_exceptions
from google.cloud import firestore, secretmanager, storage
from requests_oauthlib import OAuth1Session

BANK_OBJECT = "free_sentences_ja.json"
POSTED_OBJECT = "x_post/posted.json"

# 投稿は日本時間の朝に出る。「前日」も日本時間で切る。
JST = timezone(timedelta(hours=9))

# Gemini に渡す候補の上限。前日分が多くてもプロンプトが膨らみすぎないようにする。
MAX_CANDIDATES = 60

# 反応を参照する直近の投稿数。だいたい10日ぶん。
RECENT_POSTS = 10

GEMINI_SECRET = "gemini-api-key"
GEMINI_MODEL = "gemini-3.1-flash-lite"
GEMINI_ENDPOINT = (
    "https://generativelanguage.googleapis.com/v1beta/models/"
    "{model}:generateContent"
)

# 選定プロンプトは外に置く。書き換えて選び方を変えられるようにするため。
PROMPT_FILE = Path(__file__).with_name("select_prompt.txt")

RECENT_SECTION = """
参考までに、このアカウントの直近の投稿と反応です。伸びたものに近い題材や
語り口を優先してください（そのまま真似る必要はありません）。

{lines}
"""


def load_prompt(path: Path) -> str:
    """プロンプトを読む。`#` で始まる行は覚え書きとして落とす。"""
    lines = [
        line
        for line in path.read_text(encoding="utf-8").splitlines()
        if not line.startswith("#")
    ]
    return "\n".join(lines).strip()


def sentence_key(sentence: dict) -> str:
    """例文の同一性はタイ語本文で見る。出どころが変わってもぶれない。"""
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


def yesterday_range(now: datetime) -> tuple[datetime, datetime]:
    """日本時間での前日 00:00〜24:00。"""
    today = now.astimezone(JST).replace(
        hour=0, minute=0, second=0, microsecond=0
    )
    return today - timedelta(days=1), today


def fetch_yesterday(project: str, now: datetime) -> list[dict]:
    """前日に生成された例文を集める。タイ語本文が同じものは1件にまとめる。"""
    since, until = yesterday_range(now)
    client = firestore.Client(project=project)
    query = (
        client.collection_group("sentences")
        .where(filter=firestore.FieldFilter("created_at", ">=", since))
        .where(filter=firestore.FieldFilter("created_at", "<", until))
    )

    unique: dict[str, dict] = {}
    for doc in query.stream():
        data = doc.to_dict() or {}
        if not data.get("thai_text") or not data.get("japanese_translation"):
            continue
        unique.setdefault(sentence_key(data), data)
    return list(unique.values())


# 発音表記に算用数字が残っていたら、数字が読みに変換されていない
# （例: 「50 บาท」が「5 bàat」）。生成側の取りこぼしなので投稿には回さない。
_DIGITS = re.compile(r"[0-9\u0e50-\u0e59]")


def looks_broken(sentence: dict) -> bool:
    """機械的に分かる破綻だけ弾く。中身の自然さの判断は Gemini に任せる。"""
    thai = sentence.get("thai_text") or ""
    pronunciation = sentence.get("pronunciation") or ""
    japanese = sentence.get("japanese_translation") or ""

    if not thai or not pronunciation or not japanese:
        return True
    if _DIGITS.search(pronunciation):
        return True
    # 画像1枚に収まらない長さは詳細画面の見栄えが崩れる。
    if len(thai) > 80:
        return True

    breakdown = sentence.get("word_breakdown") or []
    if not breakdown:
        return True
    # 分解した単語が本文に無い＝分解がずれている。
    for word in breakdown:
        text = (word or {}).get("word") or ""
        if not text or text not in thai:
            return True
    return False


def recent_performance(history: list[dict]) -> list[dict]:
    """直近の投稿に反応の数を突き合わせて返す。引けなければ空。

    X の読み取りは PPU のクレジットを消費する。クレジットが無い（402）・
    鍵が無い・そもそも履歴がまだ無いといった場合は黙って諦め、反応を
    参照しない選定に落とす。投稿を止めないことを優先する。
    """
    recent = [h for h in history if h.get("tweet_id")][-RECENT_POSTS:]
    if not recent:
        return []

    keys = [
        "X_API_KEY",
        "X_API_SECRET",
        "X_ACCESS_TOKEN",
        "X_ACCESS_TOKEN_SECRET",
    ]
    if any(not os.environ.get(k) for k in keys):
        return []

    session = OAuth1Session(*(os.environ[k] for k in keys))
    try:
        response = session.get(
            "https://api.x.com/2/tweets",
            params={
                "ids": ",".join(h["tweet_id"] for h in recent),
                "tweet.fields": "public_metrics",
            },
            timeout=30,
        )
        if response.status_code != 200:
            print(
                f"反応の取得を諦める: {response.status_code} "
                f"{response.text[:120]}",
                file=sys.stderr,
            )
            return []
        metrics = {
            t["id"]: t.get("public_metrics", {})
            for t in response.json().get("data", [])
        }
    except requests.RequestException as error:
        print(f"反応の取得に失敗: {error}", file=sys.stderr)
        return []

    scored = []
    for entry in recent:
        m = metrics.get(entry["tweet_id"])
        if m is None:
            continue
        # いいね・リポスト・返信を同じ重みで足す。表示回数は投稿時刻に
        # 引きずられるので使わない。
        score = (
            m.get("like_count", 0)
            + m.get("retweet_count", 0)
            + m.get("reply_count", 0)
        )
        scored.append({**entry, "score": score})
    return scored


def performance_section(history: list[dict]) -> str:
    """履歴に反応を突き合わせて、プロンプトに差し込む節を組む。"""
    if not history:
        return ""
    ranked = sorted(history, key=lambda h: -h["score"])
    lines = "\n".join(
        f"- 反応 {h['score']:>4} / {h['thai_text']} / {h['japanese_translation']}"
        for h in ranked
    )
    return RECENT_SECTION.format(lines=lines)


def gemini_key(project: str) -> str:
    client = secretmanager.SecretManagerServiceClient()
    name = f"projects/{project}/secrets/{GEMINI_SECRET}/versions/latest"
    return client.access_secret_version(
        request={"name": name}
    ).payload.data.decode("utf-8")


def choose_with_gemini(
    project: str, candidates: list[dict], recent: str, prompt: str
) -> dict | None:
    """Gemini に1件選ばせる。失敗したら None を返して呼び出し側で抽選に落とす。"""
    listed = "\n".join(
        f"{i}. {c['thai_text']} / {c.get('pronunciation', '')} / "
        f"{c['japanese_translation']}"
        for i, c in enumerate(candidates)
    )
    body = json.dumps(
        {
            "contents": [
                {
                    "role": "user",
                    "parts": [
                        {
                            "text": prompt.format(
                                candidates=listed, recent=recent
                            )
                        }
                    ],
                }
            ],
            "generationConfig": {"temperature": 0.4, "maxOutputTokens": 16},
        }
    ).encode("utf-8")

    request = urllib.request.Request(
        GEMINI_ENDPOINT.format(model=GEMINI_MODEL),
        data=body,
        headers={
            "Content-Type": "application/json",
            "x-goog-api-key": gemini_key(project),
        },
    )
    # macOS の Python は OS の証明書ストアを見ないので certifi を明示する。
    context = ssl.create_default_context(cafile=certifi.where())
    try:
        with urllib.request.urlopen(
            request, timeout=60, context=context
        ) as response:
            payload = json.loads(response.read())
        text = payload["candidates"][0]["content"]["parts"][0]["text"]
        index = int("".join(ch for ch in text if ch.isdigit()))
        return candidates[index]
    except (urllib.error.URLError, KeyError, IndexError, ValueError) as error:
        print(f"Gemini での選定に失敗、抽選に落とす: {error}", file=sys.stderr)
        return None


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", required=True)
    parser.add_argument("--out", default="build/x_post")
    parser.add_argument(
        "--seed",
        default="",
        help="抽選の種。Gemini を使わないときの再現用。",
    )
    parser.add_argument(
        "--prompt",
        default=str(PROMPT_FILE),
        help="選定プロンプトのファイル。",
    )
    parser.add_argument(
        "--source",
        choices=["daily", "bank"],
        default="daily",
        help="daily は前日生成分、bank は free 例文バンク。",
    )
    args = parser.parse_args()

    bucket = storage.Client(project=args.project).bucket(
        f"{args.project}-uvm-data"
    )
    state = load_json(bucket, POSTED_OBJECT, {})
    posted = set(state.get("posted", []))
    now = datetime.now(timezone.utc)

    pool: list[dict] = []
    if args.source == "daily":
        try:
            pool = fetch_yesterday(args.project, now)
        except gcp_exceptions.GoogleAPIError as error:
            # 索引の準備待ちや権限不足でも投稿は止めない。
            print(f"前日分の取得に失敗: {error}", file=sys.stderr)
        if not pool:
            print("前日分が無いのでバンクに落とす", file=sys.stderr)

    if not pool:
        pool = load_json(bucket, BANK_OBJECT, [])
    if not pool:
        print(f"候補が無い: gs://{bucket.name}/{BANK_OBJECT}", file=sys.stderr)
        return 1

    sound = [s for s in pool if not looks_broken(s)]
    if sound:
        print(f"破綻を除いて {len(sound)}/{len(pool)} 件", file=sys.stderr)
        pool = sound
    else:
        # 全部弾いてしまったら選びようがない。投稿を止めるよりは出す。
        print("破綻していない候補が無いので全体から選ぶ", file=sys.stderr)

    candidates = [s for s in pool if sentence_key(s) not in posted]
    if not candidates:
        # 一巡したら投稿済みを無視して最初から回す。止まるよりは繰り返す。
        print("未投稿の例文が尽きたので全体から選ぶ", file=sys.stderr)
        candidates = pool

    rng = random.Random(args.seed or None)
    if len(candidates) > MAX_CANDIDATES:
        candidates = rng.sample(candidates, MAX_CANDIDATES)

    recent = performance_section(recent_performance(state.get("history", [])))
    picked = choose_with_gemini(
        args.project, candidates, recent, load_prompt(Path(args.prompt))
    ) or rng.choice(candidates)

    # 詳細画面は作成日を出す。Firestore の Timestamp はそのままでは JSON に
    # できないので、投稿日に置き換えて「不明」を出さない。
    picked = dict(picked)
    picked["created_at"] = now.astimezone(JST).isoformat()
    # UVM 由来の内部フィールドは投稿画面に出ないので落とす。
    picked = {k: v for k, v in picked.items() if _serializable(v)}

    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    (out / "sentence.json").write_text(
        json.dumps(picked, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    (out / "text.txt").write_text(build_text(picked), encoding="utf-8")
    (out / "key.txt").write_text(sentence_key(picked), encoding="utf-8")

    print(picked["thai_text"])
    return 0


def _serializable(value) -> bool:
    try:
        json.dumps(value)
        return True
    except TypeError:
        return False


if __name__ == "__main__":
    raise SystemExit(main())
