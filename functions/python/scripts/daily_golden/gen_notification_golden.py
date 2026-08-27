"""daily_sentence_handlers.py の通知文面を Python 実装から書き出す。

Go 版 internal/dailysentence.BuildNotificationText との差分テスト
（functions/go/internal/dailysentence/notification_golden_test.go）に使う。
出力先: functions/python/scripts/daily_golden/notification_golden.json
"""

import json
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", ".."))

from daily_sentence_handlers import build_notification_text  # noqa: E402

# 各フィールドは「無い / 空 / 空白のみ / 前後に空白 / 通常」を網羅する。
KEY_WORDS = [None, "", "   ", " กิน ", "กิน"]
MEANINGS = [None, "", "  ", " 食べる ", "食べる"]
THAI = [None, "", " ", " ผมกินข้าว ", "ผมกินข้าว"]
PRONS = [None, "", "   ", " phom kin khaao ", "phom-kin khaao"]
TRANSLATIONS = [None, "", " ", " 私はご飯を食べます ", "I eat rice"]
LANGS = ["ja", "en"]


def main() -> None:
    cases = []
    for lang in LANGS:
        for i in range(len(KEY_WORDS)):
            for j in range(len(THAI)):
                sentence = {}
                # None のキーは「キーごと欠ける」を再現するため入れない。
                for key, value in (
                    ("key_word", KEY_WORDS[i]),
                    ("key_word_meaning", MEANINGS[(i + j) % len(MEANINGS)]),
                    ("thai_text", THAI[j]),
                    ("pronunciation", PRONS[(i + 2 * j) % len(PRONS)]),
                    ("japanese_translation", TRANSLATIONS[(2 * i + j) % len(TRANSLATIONS)]),
                ):
                    if value is not None:
                        sentence[key] = value
                title, body = build_notification_text(sentence, lang)
                cases.append({
                    "sentence": sentence,
                    "lang": lang,
                    "title": title,
                    "body": body,
                })

    # 未知の言語は ja へ落ちること。normalize_lang 済みの値しか来ないが、
    # 落ち先が変わると en ユーザーの通知だけ壊れるので固定しておく。
    for lang in ["", "th", "ja-JP"]:
        sentence = {"key_word": "กิน", "key_word_meaning": "食べる",
                    "thai_text": "ผมกินข้าว", "pronunciation": "phom kin khaao",
                    "japanese_translation": "私はご飯を食べます"}
        title, body = build_notification_text(sentence, lang)
        cases.append({"sentence": sentence, "lang": lang, "title": title, "body": body})

    out = os.path.join(os.path.dirname(__file__), "notification_golden.json")
    with open(out, "w") as f:
        json.dump({"cases": cases}, f, ensure_ascii=False)
    print(f"wrote cases={len(cases)} -> {out}", file=sys.stderr)


main()
