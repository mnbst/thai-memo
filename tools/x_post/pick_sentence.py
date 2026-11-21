"""X 投稿に使う例文を1件選ぶ。

候補は GCS の静的コーパスとプール。枠（--slot）ごとに、過去の表示回数からテーマを
コードで決め、テーマと語数で絞った候補から1件を均等に抽選する。

投稿済みと履歴は gs://<project>-uvm-data/x_post/posted.json（X）と
x_post/threads/posted.json（Threads）で管理する（--platform で切り替える）。
例文は X と Threads で別の文にするので、両方の投稿済みを外して選ぶ。
--lang で投稿するアカウントの言語（訳の言語）を切り替える。ja 以外は記録を
x_post/<lang>/ に分け、候補はその言語のコーパス。
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
import statistics
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path
from zoneinfo import ZoneInfo

import requests
from google.cloud import storage
from requests_oauthlib import OAuth1Session

from pick_study_post import TWEET_LIMIT, weighted_length
from platforms import LANGS, PLATFORMS, post_id, posted_object

# premium と同じ静的コーパスと、運用中に貯めたプール（CorpusBank と同じ2本）。
# 静的コーパスはプールへ移して空にしたので、両方を読む。訳はどの言語でも
# japanese_translation に入り、context.topic は日本語のテーマ名のまま。
def corpus_objects(lang: str) -> tuple[str, str]:
    return (f"corpus_sentences_{lang}.json", f"corpus_pool_{lang}.json")

# 投稿は日本時間の朝に出る。「前日」も日本時間で切る。
JST = timezone(timedelta(hours=9))

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

# 品詞ラベル。プールは言語によらず日本語の品詞で持つので、ja 以外は投稿画面に出す前に
# 差し替える。functions/go/internal/thainlp/enrich.go の posLabelEN / posLabelKO の写し。
POS_LABELS = {
    "en": {
        "名詞": "noun", "動詞": "verb", "形容詞": "adjective", "副詞": "adverb",
        "代名詞": "pronoun", "限定詞": "determiner", "前置詞": "preposition",
        "助動詞": "auxiliary", "接続詞": "conjunction", "助詞": "particle",
        "感嘆詞": "interjection", "数詞": "numeral", "固有名詞": "proper noun",
        "句読点": "punctuation", "類別詞": "classifier", "否定詞": "negator",
        "その他": "other",
    },
    "ko": {
        "名詞": "명사", "動詞": "동사", "形容詞": "형용사", "副詞": "부사",
        "代名詞": "대명사", "限定詞": "한정사", "前置詞": "전치사",
        "助動詞": "조동사", "接続詞": "접속사", "助詞": "조사",
        "感嘆詞": "감탄사", "数詞": "수사", "固有名詞": "고유 명사",
        "句読点": "문장 부호", "類別詞": "분류사", "否定詞": "부정어",
        "その他": "기타",
    },
}


def localize_pos(sentence: dict, lang: str) -> dict:
    """単語分解の品詞を訳文の言語に合わせる。知らないラベルはそのまま。"""
    labels = POS_LABELS.get(lang)
    if not labels:
        return sentence
    words = []
    for word in sentence.get("word_breakdown") or []:
        word = dict(word or {})
        role = word.get("grammatical_role")
        if role in labels:
            word["grammatical_role"] = labels[role]
        words.append(word)
    return {**sentence, "word_breakdown": words}


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


def sentence_key(sentence: dict) -> str:
    """例文の同一性はタイ語本文で見る。出どころが変わってもぶれない。"""
    return hashlib.sha1(sentence["thai_text"].encode("utf-8")).hexdigest()


def load_json(bucket: storage.Bucket, name: str, fallback):
    blob = bucket.blob(name)
    if not blob.exists():
        return fallback
    return json.loads(blob.download_as_bytes())


# 書き出しが使えなかったときの代わり。1行目がタイ語だと読み飛ばされるので必ず入れる。
FALLBACK_HOOKS = {
    "ja": {
        "タイ旅行": "タイ旅行の時のひとこと",
        "タイ生活": "タイ暮らしの時のひとこと",
        "恋愛": "恋人と話す時のひとこと",
        "仕事": "職場で話す時のひとこと",
        "BLドラマ": "BLドラマのあの場面のセリフ",
        "推し活": "推し活の時のひとこと",
    },
    "en": {
        "タイ旅行": "A phrase for your Thailand trip",
        "タイ生活": "A phrase for daily life in Thailand",
        "恋愛": "Something to say to your partner",
        "仕事": "A phrase for the office",
        "BLドラマ": "A line straight out of a Thai BL drama",
        "推し活": "A phrase for fans",
    },
}
DEFAULT_HOOK = {
    "ja": "タイで話す時のひとこと",
    "en": "A phrase to use in Thailand",
}


def build_text(
    sentence: dict, hook: str = "", theme: str = "", lang: str = "ja"
) -> str:
    """投稿本文。「書き出し👇 → タイ語・読み → 訳」の順に揃える。

    書き出しが空か、入れると280字を超えるときはテーマの決まり文句に替える。
    ハッシュタグは付けない（2026-11 から。表示はおすすめ欄が中心で効きが薄い）。
    """
    body = [sentence["thai_text"]]
    if sentence.get("pronunciation"):
        body.append(sentence["pronunciation"])
    body += ["", sentence["japanese_translation"]]
    text = ""
    # 英語は語と絵文字の間を空ける。
    point = " 👇" if lang == "en" else "👇"
    for h in (hook, FALLBACK_HOOKS[lang].get(theme, DEFAULT_HOOK[lang])):
        if not h:
            continue
        text = "\n".join([h.rstrip("👇").rstrip() + point, ""] + body)
        if weighted_length(text) <= TWEET_LIMIT:
            return text
    return "\n".join(body)


# 発音表記に算用数字が残っていたら、数字が読みに変換されていない
# （例: 「50 บาท」が「5 bàat」）。生成側の取りこぼしなので投稿には回さない。
_DIGITS = re.compile(r"[0-9\u0e50-\u0e59]")


def looks_broken(sentence: dict) -> bool:
    """機械的に分かる破綻だけ弾く。中身の自然さはプールの確認で見ている。"""
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
        if post_id(h) and h.get("theme") in THEMES and post_slot(h) == slot
    ]


def refresh_metrics(
    history: list[dict], slot: str, now: datetime, platform: str
) -> dict:
    """同じ枠で、表示回数が未取得か、まだ確定していない投稿の数字を取り直す。"""
    stale = [
        post_id(h)
        for h in slot_history(history, slot)
        if "impressions" not in h or not settled(h, now)
    ][-FETCH_LIMIT:]
    if platform == "threads":
        return fetch_threads_metrics(stale)
    if platform == "youtube":
        from post_to_youtube import fetch_youtube_metrics

        return fetch_youtube_metrics(stale)
    return fetch_metrics(stale)


def fetch_threads_metrics(post_ids: list[str]) -> dict[str, dict]:
    """投稿ごとの表示回数と反応の数を Threads のインサイトから引く。引けなければ空。

    1件ずつ問い合わせる（まとめて引く口が無い）。読み取りは無料。
    """
    token = os.environ.get("THREADS_ACCESS_TOKEN")
    if not post_ids or not token:
        return {}
    result = {}
    for pid in post_ids:
        try:
            response = requests.get(
                f"https://graph.threads.net/v1.0/{pid}/insights",
                params={
                    "metric": "views,likes,replies,reposts",
                    "access_token": token,
                },
                timeout=30,
            )
        except requests.RequestException as error:
            print(f"反応の取得に失敗: {error}", file=sys.stderr)
            return result
        if response.status_code != 200:
            print(
                f"反応の取得を諦める: {response.status_code} "
                f"{response.text[:120]}",
                file=sys.stderr,
            )
            return result
        values = {}
        for metric in response.json().get("data", []):
            points = metric.get("values") or [metric.get("total_value") or {}]
            values[metric.get("name")] = points[0].get("value", 0) if points else 0
        # X と同じく、いいね・リポスト・返信を同じ重みで足す。
        result[pid] = {
            "impressions": values.get("views", 0),
            "score": values.get("likes", 0)
            + values.get("reposts", 0)
            + values.get("replies", 0),
        }
    return result


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
    # 絞り込んだ候補から均等に抽選する。書き出しはテーマの決まり文句を使う。
    picked, reason, hook, chooser = rng.choice(candidates), "", "", "抽選"
    print(f"候補 {len(candidates)} 件から抽選", file=sys.stderr)

    # 詳細画面は作成日を出す。Firestore の Timestamp はそのままでは JSON に
    # できないので、投稿日に置き換えて「不明」を出さない。
    picked = dict(picked)
    picked["created_at"] = now.isoformat()
    # UVM 由来の内部フィールドは投稿画面に出ないので落とす。
    picked = {k: v for k, v in picked.items() if _serializable(v)}
    picked = localize_pos(picked, lang)

    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    (out / "sentence.json").write_text(
        json.dumps(picked, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    text = build_text(picked, hook, theme, lang)
    # 実際に使った書き出し（決まり文句に替わった場合も含む）を履歴に残す。
    first = text.splitlines()[0]
    hook = first if first.endswith("👇") else ""
    (out / "text.txt").write_text(text, encoding="utf-8")
    (out / "key.txt").write_text(sentence_key(picked), encoding="utf-8")
    (out / "theme.txt").write_text(theme, encoding="utf-8")
    # 取り直した数字は post_to_x.py / post_to_threads.py が posted.json の履歴へ書き戻す。
    (out / "metrics.json").write_text(json.dumps(fetched), encoding="utf-8")
    # 選んだ文脈。post_to_x.py が履歴に残し、次の回の判断材料にする。
    (out / "selection.json").write_text(
        json.dumps(
            {
                "slot": slot,
                "weekday": weekday,
                "theme_reason": theme_reason,
                "reason": reason,
                "hook": hook,
                "chooser": chooser,
                **features(picked),
            },
            ensure_ascii=False,
        ),
        encoding="utf-8",
    )

    print(picked["thai_text"])
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", required=True)
    parser.add_argument("--out", default="build/x_post")
    parser.add_argument(
        "--seed",
        default="",
        help="抽選の種。再現用。",
    )
    parser.add_argument(
        "--themes",
        default="",
        help=f"抽選するテーマをカンマ区切りで。空なら全部。候補: {','.join(THEMES)}",
    )
    parser.add_argument(
        "--slot",
        default="",
        help="投稿の枠（0700 など）。空なら今の --tz の時から決める。",
    )
    # 枠・曜日を数える時間帯。英語アカウントは米国西部に合わせる。
    parser.add_argument("--tz", default="Asia/Tokyo")
    parser.add_argument("--platform", choices=PLATFORMS, default="x")
    parser.add_argument("--lang", choices=LANGS, default="ja")
    args = parser.parse_args()
    lang = args.lang

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
    state = load_json(bucket, posted_object(args.platform, lang), {})
    # 例文は投稿先ごとに別の文にする。同じ言語のほかの投稿先で出した文も外す。
    posted = set(state.get("posted", [])).union(
        *(
            load_json(bucket, posted_object(p, lang), {}).get("posted", [])
            for p in PLATFORMS
            if p != args.platform
        )
    )
    now = datetime.now(ZoneInfo(args.tz))
    slot = args.slot or f"{now.hour:02d}00"
    weekday = now.weekday()

    # 同じ本文が両方にあれば先に読んだほうを残す。
    corpus = list(
        {
            sentence_key(s): s
            for name in reversed(corpus_objects(lang))
            for s in load_json(bucket, name, [])
        }.values()
    )
    if not corpus:
        print(
            f"コーパスが無い: gs://{bucket.name}/{corpus_objects(lang)}",
            file=sys.stderr,
        )
        return 1
    sound = sound_only(corpus)

    # 取り直した数字を先に履歴へ重ねる。テーマの点数も過去の投稿の並びも新しい値で見る。
    fetched = refresh_metrics(state.get("history", []), slot, now, args.platform)
    history = [{**h, **fetched.get(post_id(h), {})} for h in state.get("history", [])]

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

    picked = rng.choice(candidates)
    reason, hook, chooser = "", "", "抽選"

    # 詳細画面は作成日を出す。Firestore の Timestamp はそのままでは JSON に
    # できないので、投稿日に置き換えて「不明」を出さない。
    picked = dict(picked)
    picked["created_at"] = now.isoformat()
    # UVM 由来の内部フィールドは投稿画面に出ないので落とす。
    picked = {k: v for k, v in picked.items() if _serializable(v)}
    picked = localize_pos(picked, lang)

    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    (out / "sentence.json").write_text(
        json.dumps(picked, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    text = build_text(picked, hook, theme, lang)
    # 実際に使った書き出し（決まり文句に替わった場合も含む）を履歴に残す。
    first = text.splitlines()[0]
    hook = first if first.endswith("👇") else ""
    (out / "text.txt").write_text(text, encoding="utf-8")
    (out / "key.txt").write_text(sentence_key(picked), encoding="utf-8")
    (out / "theme.txt").write_text(theme, encoding="utf-8")
    # 取り直した数字は post_to_x.py / post_to_threads.py が posted.json の履歴へ書き戻す。
    (out / "metrics.json").write_text(json.dumps(fetched), encoding="utf-8")
    # 選んだ文脈。post_to_x.py が履歴に残し、次の回の判断材料にする。
    (out / "selection.json").write_text(
        json.dumps(
            {
                "slot": slot,
                "weekday": weekday,
                "theme_reason": theme_reason,
                "reason": reason,
                "hook": hook,
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
