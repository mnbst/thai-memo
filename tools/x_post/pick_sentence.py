"""X 投稿に使う例文を1件選ぶ。

候補は GCS の静的コーパスとプール。枠（--slot）ごとに、過去の表示回数からテーマを
コードで決め、長さ・場面がばらけるように20件に絞る。最後の1件は、同じ枠の直近10件の
「選んだ理由・表示回数」と比べさせて Gemini に選ばせ、理由も書かせる。Gemini が使えない
ときは同じ候補から抽選して投稿を止めない。

投稿済みと履歴は gs://<project>-uvm-data/x_post/posted.json で管理する。
選んだ例文は <out>/sentence.json、投稿本文は <out>/text.txt、選んだ文脈は
<out>/selection.json に書く。実際に投稿できたかは post_to_x.py が確かめてから
posted.json を更新する。
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import random
import re
import ssl
import statistics
import sys
import urllib.error
import urllib.request
from datetime import datetime, timedelta, timezone
from pathlib import Path

import certifi
import requests
from google.cloud import secretmanager, storage
from requests_oauthlib import OAuth1Session

# premium と同じ静的コーパスと、運用中に貯めたプール（CorpusBank と同じ2本）。
# 静的コーパスはプールへ移して空にしたので、両方を読む。
CORPUS_OBJECTS = ("corpus_sentences_ja.json", "corpus_pool_ja.json")
POSTED_OBJECT = "x_post/posted.json"

# 投稿は日本時間の朝に出る。「前日」も日本時間で切る。
JST = timezone(timedelta(hours=9))

# Gemini に渡す候補の数。プロンプトの長さ（＝コスト）を抑えるため、長さ・場面が
# ばらけるように選んでからこの数に絞る。
MAX_CANDIDATES = 20
# 同じ場面の候補は何件まで渡すか。
SCENE_CAP = 2

# 選定の文脈として渡す、同じ枠の直近の投稿数。判断理由もこの数だけ残す。
RECENT_POSTS = 10
# 表示回数は2〜3日で頭打ちになる。それより新しい投稿の数字は暫定として扱い、
# X から取り直す。古い投稿は posted.json に残した値を使い、読み取りの課金を抑える。
SETTLE_DAYS = 3
# X の /2/tweets で一度に引ける ID の数。
FETCH_LIMIT = 100

# テーマ選び。枠ごとに、投稿がこの数に届いていないテーマがあれば先に試す。
EXPLORE_POSTS = 3
# 試し終えたあとも、この割合は抽選して偏りを避ける。
EXPLORE_RATE = 0.2
# 曜日の補正をかけるのに要る件数。
WEEKDAY_MIN_POSTS = 3

WEEKDAYS = "月火水木金土日"

# 投稿に回す例文の語数。短すぎると学びが薄く、長すぎると詳細画面に収まらない。
MIN_WORDS = 7
MAX_WORDS = 11

# 投稿のテーマ。--themes で渡したものから毎日1つ抽選し、コーパスの
# context.topic か subTheme が挙げた個別テーマで始まるものだけを候補にする。旅行・生活の
# 中身はアプリの「タイ旅行」「タイ暮らし」（GenerationConstants.travelTopic /
# lifeTopic）に揃える。--themes は Cloud Scheduler の起動リクエストから来る。
THEMES = {
    "タイ旅行": ("旅行", "交通", "買い物", "食べ物"),
    "タイ生活": ("買い物", "交通", "健康", "家族", "天気", "食べ物"),
    "恋愛": ("恋愛・男女関係",),
    "仕事": ("仕事",),
    "BLドラマ": ("タイBLドラマ",),
    # 独立テーマ「推し活」に加え、趣味・買い物・宗教の subTheme（推しの配信 等）も拾う。
    "推し活": ("推し",),
}

# BLドラマの日は、作品の見当がつく例文だけ出す。作品ごとに、本文か使い方
# （context.usage_scenarios）に出ればその作品と分かる語（登場人物名とそのカタカナ・
# 象徴的な小道具や場所）を並べる。人物名は必須にしない。2026-10-11 から生成側は
# 本文に名前を必須にせず、使い方に名前を書かせる。一般語と紛れる語（หมู=豚、สไตล์、ดาว、
# พระเจ้า 等）は入れない。作品の設定は functions/go/internal/bldrama/data.go の
# shotContext。
BL_DRAMA_MARKERS = {
    "Only Boo!": ("พี่แกง", "カン", "ムー", "ข้าวแกง"),
    "The Heart Killers": (
        "ไบซัน", "ฟาเดล", "คานต์", "カーン",
        "バイソン", "ファデル", "นักฆ่า",
    ),
    "Peaceful Property": ("พีช", "โฮม", "ピーチ", "ホーム", "ผี"),
    "MuTeLuv": ("มาวิน", "เอ้อ", "マーウィン", "หมอดู", "ดูดวง"),
    "Cat for Cash": ("ไทเกอร์", "ลิงซ์", "タイガー", "リンクス", "แมว"),
    "Unlucky Bae": ("ขอบฟ้า", "コープファー", "คำสาป", "ซวย"),
    "Match Point": ("เบย์", "เทนนิส", "ติ่มซำ"),
    "A Dog and A Plane": (
        "คณิต", "โตโต้", "カニット", "トートー",
        "กัปตัน", "กู้ภัย", "กระเป๋าเดินทาง",
    ),
    "When Oranges Fall": ("โก๋", "コーヌン", "コーソーン", "ส้ม"),
    "Ticket to Heaven": (
        "แทนรัก", "บาร์ธ", "タンラック",
        "バース", "บาทหลวง", "โบสถ์",
    ),
    "WEIRDO-101": ("นิรันดร์", "ชีวา", "ニラン", "チーワー", "ยูโด"),
    "You Maniac": ("ดีน", "มอธ", "モス"),
    "Only Friends: Dream On": ("แจ็ค", "ジャック", "ละคร", "เวที"),
}

GEMINI_SECRET = "gemini-api-key"
GEMINI_MODEL = "gemini-3.1-flash-lite"
GEMINI_ENDPOINT = (
    "https://generativelanguage.googleapis.com/v1beta/models/"
    "{model}:generateContent"
)

# 選定プロンプトは外に置く。書き換えて選び方を変えられるようにするため。
PROMPT_FILE = Path(__file__).with_name("select_prompt.txt")

RECENT_SECTION = """
この時間帯の過去の投稿です（古い順、最大{count}件）。「理由」はそのとき選んだ根拠です。
理由ごとに、表示回数がこの時間帯の中央値（{median}）より伸びたか外れたかを見て、
当たった理由・長さ・文法に近い候補を優先し、外れた理由と同じ狙いは避けてください。
「暫定」は投稿から{settle}日以内でまだ伸びる数字なので軽く見てください。

{lines}
"""

TREND_SECTION = """
この時間帯の長い期間の傾向（表示回数の中央値との比較）:
{lines}
"""

# 文法の特徴。単語分解の語と完全に一致したときだけ付ける（部分一致だと
# คะแนน の คะ のような誤判定が増える）。分解が語をまとめていると取りこぼすが、
# 傾向を見るには足りる。
GRAMMAR_MARKERS = {
    "疑問": (
        "ไหม", "มั้ย", "หรือเปล่า", "หรือยัง", "อะไร", "ที่ไหน", "เมื่อไร",
        "เมื่อไหร่", "ทำไม", "ยังไง", "อย่างไร", "ใคร", "เท่าไร", "เท่าไหร่",
    ),
    "依頼": ("ช่วย", "หน่อย", "ขอ", "กรุณา"),
    "否定": ("ไม่", "อย่า"),
    "勧誘": ("เถอะ", "กันเถอะ", "ด้วยกัน"),
    "丁寧語尾": ("ครับ", "ค่ะ", "คะ", "ครับผม"),
    "くだけた語尾": ("นะ", "จ้า", "จ้ะ", "น่ะ", "ล่ะ", "สิ", "ซิ", "เนอะ"),
    "時制": ("แล้ว", "กำลัง", "จะ", "เคย", "เพิ่ง"),
    "比較・程度": ("กว่า", "ที่สุด", "มาก", "เกินไป", "ค่อนข้าง"),
}


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


# 投稿の末尾に付けるハッシュタグ。テスター募集の投稿と揃える。
HASHTAGS = "#タイ語 #タイ語勉強"


def build_text(sentence: dict) -> str:
    """投稿本文。"""
    lines = [sentence["thai_text"]]
    if sentence.get("pronunciation"):
        lines.append(sentence["pronunciation"])
    lines += ["", sentence["japanese_translation"], "", HASHTAGS]
    return "\n".join(lines)


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
    if not MIN_WORDS <= len(breakdown) <= MAX_WORDS:
        return True
    # 分解した単語が本文に無い＝分解がずれている。
    for word in breakdown:
        text = (word or {}).get("word") or ""
        if not text or text not in thai:
            return True
    return False


def sound_only(pool: list[dict]) -> list[dict]:
    """破綻と語数で候補を絞る。残らなければ空を返して呼び出し側に落とさせる。"""
    if not pool:
        return []
    sound = [s for s in pool if not looks_broken(s)]
    print(f"破綻を除いて {len(sound)}/{len(pool)} 件", file=sys.stderr)
    return sound


def theme_only(pool: list[dict], theme: str) -> list[dict]:
    """テーマに含まれる個別テーマだけ残す。トピックが無い例文は落とす。"""
    prefixes = THEMES[theme]

    def in_theme(sentence: dict) -> bool:
        context = sentence.get("context") or {}
        topic = context.get("topic") or ""
        sub_theme = context.get("subTheme") or ""
        return topic.startswith(prefixes) or sub_theme.startswith(prefixes)

    picked = [s for s in pool if in_theme(s)]
    print(f"{theme}に絞って {len(picked)}/{len(pool)} 件", file=sys.stderr)
    return picked


def bl_drama_only(pool: list[dict], rng: random.Random) -> list[dict]:
    """作品の見当がつく例文だけ残し、そのうち1作品に絞る。

    作品で分けずに抽選すると例文の多い作品（猫・幽霊）ばかり出るので、
    先に作品を抽選する。
    """
    by_drama: dict[str, list[dict]] = {}
    for sentence in pool:
        for drama, markers in BL_DRAMA_MARKERS.items():
            text = sentence["thai_text"] + (
                (sentence.get("context") or {}).get("usage_scenarios") or ""
            )
            if any(m in text for m in markers):
                by_drama.setdefault(drama, []).append(sentence)
                break
    if not by_drama:
        return []
    drama = rng.choice(sorted(by_drama))
    print(f"作品: {drama}（{len(by_drama[drama])}件）", file=sys.stderr)
    return by_drama[drama]


def word_count(sentence: dict) -> int:
    return len(sentence.get("word_breakdown") or [])


def length_band(n: int) -> str:
    if n <= 8:
        return "7–8語"
    if n <= 10:
        return "9–10語"
    return "11語"


def scene_of(sentence: dict) -> str:
    context = sentence.get("context") or {}
    return context.get("subTheme") or context.get("topic") or ""


def grammar_tags(sentence: dict) -> list[str]:
    words = {(w or {}).get("word") or "" for w in sentence.get("word_breakdown") or []}
    return [
        tag for tag, markers in GRAMMAR_MARKERS.items() if words.intersection(markers)
    ]


def features(sentence: dict) -> dict:
    """投稿の記録に残す例文の特徴。過去の投稿と比べる材料にする。"""
    return {
        "word_count": word_count(sentence),
        "char_count": len(sentence["thai_text"]),
        "scene": scene_of(sentence),
        "grammar": grammar_tags(sentence),
    }


def posted_at(entry: dict) -> datetime | None:
    try:
        return datetime.fromisoformat(entry["posted_at"]).astimezone(JST)
    except (KeyError, ValueError):
        return None


def post_slot(entry: dict) -> str:
    """投稿の枠。枠を記録する前の投稿は投稿時刻から割り出す（指定時刻の
    数分後に出るので、時の値がそのまま枠になる）。"""
    if entry.get("slot"):
        return entry["slot"]
    at = posted_at(entry)
    return f"{at.hour:02d}00" if at else ""


def post_weekday(entry: dict) -> int | None:
    if "weekday" in entry:
        return entry["weekday"]
    at = posted_at(entry)
    return at.weekday() if at else None


def settled(entry: dict, now: datetime) -> bool:
    at = posted_at(entry)
    return at is not None and now - at >= timedelta(days=SETTLE_DAYS)


def slot_history(history: list[dict], slot: str) -> list[dict]:
    """同じ枠の例文の投稿。Tips・ガイドはテーマが THEMES に無いので落ちる。"""
    return [
        h
        for h in history
        if h.get("tweet_id") and h.get("theme") in THEMES and post_slot(h) == slot
    ]


def refresh_metrics(history: list[dict], slot: str, now: datetime) -> dict:
    """同じ枠で、表示回数が未取得か、まだ確定していない投稿の数字を取り直す。"""
    stale = [
        h["tweet_id"]
        for h in slot_history(history, slot)
        if "impressions" not in h or not settled(h, now)
    ][-FETCH_LIMIT:]
    return fetch_metrics(stale)


def fetch_metrics(tweet_ids: list[str]) -> dict[str, dict]:
    """投稿ごとの表示回数と反応の数を X から引く。引けなければ空。"""
    if not tweet_ids:
        return {}

    keys = [
        "X_API_KEY",
        "X_API_SECRET",
        "X_ACCESS_TOKEN",
        "X_ACCESS_TOKEN_SECRET",
    ]
    if any(not os.environ.get(k) for k in keys):
        return {}

    session = OAuth1Session(*(os.environ[k] for k in keys))
    try:
        response = session.get(
            "https://api.x.com/2/tweets",
            params={
                "ids": ",".join(tweet_ids),
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
            return {}
        metrics = {
            t["id"]: t.get("public_metrics", {})
            for t in response.json().get("data", [])
        }
    except requests.RequestException as error:
        print(f"反応の取得に失敗: {error}", file=sys.stderr)
        return {}

    # いいね・リポスト・返信を同じ重みで足す。
    return {
        tweet_id: {
            "impressions": m.get("impression_count", 0),
            "score": m.get("like_count", 0)
            + m.get("retweet_count", 0)
            + m.get("reply_count", 0),
        }
        for tweet_id, m in metrics.items()
    }


def _median_impressions(entries: list[dict]) -> float | None:
    values = [h["impressions"] for h in entries if "impressions" in h]
    return statistics.median(values) if values else None


def weekday_factor(
    history: list[dict], theme: str, weekday: int
) -> tuple[float, str]:
    """そのテーマの曜日の伸びやすさ（全体の中央値との比）。件数が足りなければ
    平日／週末でまとめ、それでも足りなければ補正しない。"""
    mine = [h for h in history if h.get("theme") == theme and "impressions" in h]
    overall = _median_impressions(mine)
    if not overall:
        return 1.0, ""
    weekend = weekday >= 5
    for label, same in (
        (f"{WEEKDAYS[weekday]}曜", lambda d: d == weekday),
        ("週末" if weekend else "平日", lambda d: d is not None and (d >= 5) == weekend),
    ):
        group = [h for h in mine if same(post_weekday(h))]
        if len(group) >= WEEKDAY_MIN_POSTS:
            return _median_impressions(group) / overall, label
    return 1.0, ""


def choose_theme(
    history: list[dict],
    slot: str,
    weekday: int,
    themes: list[str],
    rng: random.Random,
) -> tuple[list[str], str]:
    """枠と曜日からテーマの順位を決める。候補が無いテーマは呼び出し側が飛ばす。

    まだ試していないテーマ（枠の中で EXPLORE_POSTS 件未満）があればそれを先に、
    試し終えたら EXPLORE_RATE の割合で抽選し、残りは点数の高い順にする。
    点数 ＝ 枠×テーマの表示回数の中央値 × 曜日の補正。
    """
    mine = slot_history(history, slot)
    counts = {t: sum(1 for h in mine if h["theme"] == t) for t in themes}
    shuffled = rng.sample(themes, len(themes))

    unexplored = [t for t in shuffled if counts[t] < EXPLORE_POSTS]
    if unexplored:
        rest = [t for t in shuffled if t not in unexplored]
        first = unexplored[0]
        return unexplored + rest, f"探索（{slot}で{first}は{counts[first]}件）"
    if rng.random() < EXPLORE_RATE:
        return shuffled, "抽選（偏り防止）"

    scores: dict[str, tuple[float, str]] = {}
    for theme in themes:
        base = _median_impressions([h for h in mine if h["theme"] == theme]) or 0
        factor, label = weekday_factor(history, theme, weekday)
        n = sum(1 for h in mine if h["theme"] == theme and "impressions" in h)
        note = f"{slot}の中央値{base:.0f}（{n}件）"
        if label:
            note += f"×{label}補正{factor:.2f}"
        scores[theme] = (base * factor, note)
    ranked = sorted(themes, key=lambda t: -scores[t][0])
    return ranked, f"点数最大: {scores[ranked[0]][1]}"


def diverse_sample(
    candidates: list[dict], recent_scenes: set[str], rng: random.Random
) -> list[dict]:
    """長さの帯から同じ数ずつ、同じ場面は SCENE_CAP 件までで MAX_CANDIDATES 件に絞る。

    直近の投稿と同じ場面は後回しにする。足りなければ外したもので埋める。
    """
    bands: dict[str, list[dict]] = {}
    for sentence in rng.sample(candidates, len(candidates)):
        bands.setdefault(length_band(word_count(sentence)), []).append(sentence)
    queues = [
        sorted(bands[b], key=lambda s: scene_of(s) in recent_scenes)
        for b in sorted(bands)
    ]

    picked: list[dict] = []
    skipped: list[dict] = []
    per_scene: dict[str, int] = {}
    while len(picked) < MAX_CANDIDATES and any(queues):
        for queue in queues:
            while queue and len(picked) < MAX_CANDIDATES:
                sentence = queue.pop(0)
                scene = scene_of(sentence)
                if per_scene.get(scene, 0) >= SCENE_CAP:
                    skipped.append(sentence)
                    continue
                per_scene[scene] = per_scene.get(scene, 0) + 1
                picked.append(sentence)
                break
    return picked + skipped[: MAX_CANDIDATES - len(picked)]


def when_label(slot: str, weekday: int) -> str:
    """プロンプトに渡す「いつ読まれるか」。"""
    hour = int(slot[:2]) if slot[:2].isdigit() else 12
    if 5 <= hour < 10:
        scene = "朝・通勤や始業前"
    elif hour < 14:
        scene = "昼休み前後"
    elif hour < 19:
        scene = "夕方・帰り道"
    else:
        scene = "夜・くつろぎ"
    day = {4: "週末前", 5: "週末", 6: "週末・休み明け前"}.get(weekday, "平日")
    return f"{WEEKDAYS[weekday]}曜 {slot[:2]}:{slot[2:]}（{scene}・{day}）"


def recent_section(mine: list[dict], now: datetime) -> str:
    """同じ枠の直近の投稿を、選んだ理由と表示回数を並べて組む。"""
    recent = mine[-RECENT_POSTS:]
    if not recent:
        return ""
    lines = []
    for h in recent:
        at = posted_at(h)
        weekday = post_weekday(h)
        day = f"{at:%m/%d}({WEEKDAYS[weekday]})" if at and weekday is not None else "?"
        length = f"{h['word_count']}語" if "word_count" in h else "-"
        grammar = ",".join(h.get("grammar") or []) or "-"
        if "impressions" in h:
            numbers = f"表示 {h['impressions']} 反応 {h.get('score', 0)}"
            if not settled(h, now):
                numbers += "（暫定）"
        else:
            numbers = "表示 未取得"
        reason = h.get("reason") or "記録なし"
        lines.append(
            f"- {day} {h['theme']} {length} {grammar} {numbers} / "
            f"{h.get('japanese_translation', '')} / 理由: {reason}"
        )
    median = _median_impressions(mine)
    return RECENT_SECTION.format(
        count=RECENT_POSTS,
        median=f"{median:.0f}" if median is not None else "不明",
        settle=SETTLE_DAYS,
        lines="\n".join(lines),
    )


def trend_section(mine: list[dict]) -> str:
    """枠全体で、長さ・文法ごとに中央値より伸びたもの・伸びなかったものを数行で。"""
    overall = _median_impressions(mine)
    if not overall:
        return ""
    groups: dict[str, list[dict]] = {}
    for h in mine:
        if "impressions" not in h or "word_count" not in h:
            continue
        groups.setdefault(length_band(h["word_count"]), []).append(h)
        for tag in h.get("grammar") or []:
            groups.setdefault(tag, []).append(h)
    ratios = {
        name: _median_impressions(entries) / overall
        for name, entries in groups.items()
        if len(entries) >= 2
    }
    if not ratios:
        return ""
    ranked = sorted(ratios, key=lambda k: -ratios[k])
    up = [f"{k}（×{ratios[k]:.2f}）" for k in ranked if ratios[k] > 1][:3]
    down = [f"{k}（×{ratios[k]:.2f}）" for k in reversed(ranked) if ratios[k] < 1][:3]
    lines = []
    if up:
        lines.append("- 伸びやすい: " + " / ".join(up))
    if down:
        lines.append("- 伸びにくい: " + " / ".join(down))
    return TREND_SECTION.format(lines="\n".join(lines))


def gemini_key(project: str) -> str:
    client = secretmanager.SecretManagerServiceClient()
    name = f"projects/{project}/secrets/{GEMINI_SECRET}/versions/latest"
    return client.access_secret_version(
        request={"name": name}
    ).payload.data.decode("utf-8")


def choose_with_gemini(
    project: str, candidates: list[dict], prompt: str
) -> tuple[dict, str] | None:
    """Gemini に1件選ばせ、選んだ例文と理由を返す。失敗したら None を返して
    呼び出し側で抽選に落とす。"""
    body = json.dumps(
        {
            "contents": [{"role": "user", "parts": [{"text": prompt}]}],
            "generationConfig": {
                "temperature": 0.4,
                # 理由は60字まで。思考は使わず、出力の上限で費用を抑える。
                "maxOutputTokens": 256,
                "thinkingConfig": {"thinkingLevel": "minimal"},
                "responseMimeType": "application/json",
                "responseSchema": {
                    "type": "object",
                    "properties": {
                        "index": {"type": "integer"},
                        "reason": {"type": "string"},
                    },
                    "required": ["index", "reason"],
                },
            },
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
        answer = json.loads(text)
        index = int(answer["index"])
        if not 0 <= index < len(candidates):
            raise IndexError(index)
        return candidates[index], str(answer["reason"]).strip()
    except (
        urllib.error.URLError,
        KeyError,
        IndexError,
        TypeError,
        ValueError,
    ) as error:
        print(f"Gemini での選定に失敗、抽選に落とす: {error}", file=sys.stderr)
        return None


def build_prompt(
    template: str,
    candidates: list[dict],
    theme: str,
    when: str,
    recent: str,
    trend: str,
) -> str:
    listed = "\n".join(
        f"{i}. {c['thai_text']} / {c['japanese_translation']} / "
        f"{word_count(c)}語 / {scene_of(c) or '-'} / "
        f"{','.join(grammar_tags(c)) or '-'}"
        for i, c in enumerate(candidates)
    )
    # プロンプトには JSON の例を書くので format は使わず、差し込み口だけ置き換える。
    for name, value in (
        ("{theme}", theme),
        ("{when}", when),
        ("{recent}", recent),
        ("{trend}", trend),
        ("{candidates}", listed),
    ):
        template = template.replace(name, value)
    return template


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
        "--themes",
        default="",
        help=f"抽選するテーマをカンマ区切りで。空なら全部。候補: {','.join(THEMES)}",
    )
    parser.add_argument(
        "--slot",
        default="",
        help="投稿の枠（0700 など）。空なら今の JST の時から決める。",
    )
    args = parser.parse_args()

    themes = [t.strip() for t in args.themes.split(",") if t.strip()] or list(
        THEMES
    )
    unknown = [t for t in themes if t not in THEMES]
    if unknown:
        print(f"知らないテーマ: {','.join(unknown)}", file=sys.stderr)
        return 1

    bucket = storage.Client(project=args.project).bucket(
        f"{args.project}-uvm-data"
    )
    state = load_json(bucket, POSTED_OBJECT, {})
    posted = set(state.get("posted", []))
    now = datetime.now(JST)
    slot = args.slot or f"{now.hour:02d}00"
    weekday = now.weekday()

    # 同じ本文が両方にあれば先に読んだほうを残す。
    corpus = list(
        {
            sentence_key(s): s
            for name in reversed(CORPUS_OBJECTS)
            for s in load_json(bucket, name, [])
        }.values()
    )
    if not corpus:
        print(f"コーパスが無い: gs://{bucket.name}/{CORPUS_OBJECTS}", file=sys.stderr)
        return 1
    sound = sound_only(corpus)

    # 取り直した数字を先に履歴へ重ねる。テーマの点数も過去の投稿の並びも新しい値で見る。
    fetched = refresh_metrics(state.get("history", []), slot, now)
    history = [
        {**h, **fetched.get(h.get("tweet_id"), {})} for h in state.get("history", [])
    ]

    rng = random.Random(args.seed or None)
    order, theme_reason = choose_theme(history, slot, weekday, themes, rng)

    # 順位の高いテーマから、候補が残るものを使う。どれも残らなければ投稿を止める。
    theme, candidates = "", []
    for theme in order:
        pool = theme_only(sound, theme)
        candidates = [s for s in pool if sentence_key(s) not in posted]
        if not candidates:
            # 一巡したら投稿済みを無視して最初から回す。止まるよりは繰り返す。
            candidates = pool
        if theme == "BLドラマ":
            candidates = bl_drama_only(candidates, rng)
        if candidates:
            break
        print(f"{theme}は候補が無いので次のテーマへ", file=sys.stderr)
    if not candidates:
        print("条件に合う候補が無い", file=sys.stderr)
        return 1
    print(f"テーマ: {theme}（{theme_reason}）", file=sys.stderr)

    mine = slot_history(history, slot)
    recent_scenes = {h.get("scene") for h in mine[-RECENT_POSTS:] if h.get("scene")}
    candidates = diverse_sample(candidates, recent_scenes, rng)

    prompt = build_prompt(
        load_prompt(Path(args.prompt)),
        candidates,
        theme,
        when_label(slot, weekday),
        recent_section(mine, now),
        trend_section(mine),
    )
    chosen = choose_with_gemini(args.project, candidates, prompt)
    if chosen:
        picked, reason = chosen
        chooser = "gemini"
    else:
        picked, reason, chooser = rng.choice(candidates), "", "抽選"
    print(f"理由: {reason or '-'}（{chooser}）", file=sys.stderr)

    # 詳細画面は作成日を出す。Firestore の Timestamp はそのままでは JSON に
    # できないので、投稿日に置き換えて「不明」を出さない。
    picked = dict(picked)
    picked["created_at"] = now.isoformat()
    # UVM 由来の内部フィールドは投稿画面に出ないので落とす。
    picked = {k: v for k, v in picked.items() if _serializable(v)}

    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    (out / "sentence.json").write_text(
        json.dumps(picked, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    (out / "text.txt").write_text(build_text(picked), encoding="utf-8")
    (out / "key.txt").write_text(sentence_key(picked), encoding="utf-8")
    (out / "theme.txt").write_text(theme, encoding="utf-8")
    # 取り直した数字は post_to_x.py が posted.json の履歴へ書き戻す。
    (out / "metrics.json").write_text(json.dumps(fetched), encoding="utf-8")
    # 選んだ文脈。post_to_x.py が履歴に残し、次の回の判断材料にする。
    (out / "selection.json").write_text(
        json.dumps(
            {
                "slot": slot,
                "weekday": weekday,
                "theme_reason": theme_reason,
                "reason": reason,
                "chooser": chooser,
                **features(picked),
            },
            ensure_ascii=False,
        ),
        encoding="utf-8",
    )

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
