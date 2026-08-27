"""constants.py の schema 組み立てと context 英語化を書き出す。

Go 版 internal/sentence との差分テストに使う。
出力先: functions/python/scripts/daily_golden/constants_golden.json
"""

import itertools
import json
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", ".."))

import constants as c  # noqa: E402

ASK_FIELDS = ["topic", "style", "emotion"]


def main() -> None:
    schema_cases = []
    # 生成させるフィールドの全組み合わせ × 言語
    for r in range(len(ASK_FIELDS) + 1):
        for combo in itertools.combinations(ASK_FIELDS, r):
            for lang in ("ja", "en"):
                schema_cases.append({
                    "ask_context_fields": list(combo),
                    "lang": lang,
                    "schema": c.build_response_schema(combo, lang),
                })
    # 未知のフィールド名は無視される
    for lang in ("ja", "en"):
        schema_cases.append({
            "ask_context_fields": ["topic", "unknown_field"],
            "lang": lang,
            "schema": c.build_response_schema(("topic", "unknown_field"), lang),
        })

    # build_response_schema は ja かつ指定なしのとき RESPONSE_JSON_SCHEMA を
    # そのまま返す（コピーしない）。後続の呼び出しが汚染されていないことを
    # 確かめるため、最後にもう一度素の形を取る。
    schema_cases.append({
        "ask_context_fields": [],
        "lang": "ja",
        "schema": c.build_response_schema((), "ja"),
    })

    # --- localize_context ---
    context_cases = []
    topics = list(c.TOPIC_LABELS_EN.keys())
    for topic in topics:
        sub_themes = list(c.SUB_THEME_LABELS_EN.get(topic, {}).keys())
        for style in list(c.STYLE_LABELS_EN.keys()) + ["未知の文体"]:
            for tf in list(c.TIME_FRAME_LABELS_EN.keys()) + ["未知の時制"]:
                for sub in (sub_themes[:2] or [None]) + ["未知のサブテーマ"]:
                    ctx = {
                        "topic": topic,
                        "style": style,
                        "timeFrame": tf,
                        "emotion": "中立",
                        "usage_scenarios": "自由記述",
                    }
                    if sub is not None:
                        ctx["subTheme"] = sub
                    for lang in ("ja", "en"):
                        context_cases.append({
                            "context": ctx,
                            "lang": lang,
                            "result": c.localize_context(ctx, lang),
                        })

    # 短縮形のテーマ（LLM が選んだ回）と、既に英語化済みのもの
    for topic in topics:
        head = topic.split("（")[0]
        for value in (head, c.TOPIC_LABELS_EN[topic], "全く未知のテーマ"):
            ctx = {"topic": value, "style": "口語体（友達同士のカジュアルな話し言葉）"}
            for lang in ("ja", "en"):
                context_cases.append({
                    "context": ctx,
                    "lang": lang,
                    "result": c.localize_context(ctx, lang),
                })

    # context が無い / 型違い
    for lang in ("ja", "en"):
        context_cases.append({"context": None, "lang": lang,
                              "result": c.localize_context(None, lang)})

    out = os.path.join(os.path.dirname(__file__), "constants_golden.json")
    with open(out, "w") as f:
        json.dump({
            "schema_cases": schema_cases,
            "context_cases": context_cases,
        }, f, ensure_ascii=False)
    print(
        f"wrote schema={len(schema_cases)} context={len(context_cases)} -> {out}",
        file=sys.stderr,
    )


main()
