"""prompts.resolve_generation_params の確定部分を Python 実装から書き出す。

抽選（timeFrame / relation）は乱数なので値そのものは比べられない。
比べるのは「クライアント指定値をそのまま通すか」「未指定のとき候補集合の
どこから引くか」「テーマ候補が語彙スコアでどう絞られるか」。

実行: functions/python/venv/bin/python scripts/daily_golden/gen_resolve_golden.py
出力: functions/python/scripts/daily_golden/resolve_golden.json
"""

import json
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", ".."))

import prompts  # noqa: E402


def main() -> None:
    out: dict = {}

    # --- 語彙スコアごとのテーマ候補（ゲート） ---
    vocabs = [0, 1, 50, 99, 100, 199, 200, 400, 500, 800, 1000, 3000, 10000]
    out["topic_options"] = [
        {
            "estimated_vocab": v,
            "options": prompts.resolve_generation_params(
                {}, is_premium=True, target_words=None, estimated_vocab=v
            )["topicOptions"],
        }
        for v in vocabs
    ]

    # --- クライアント指定値の扱い ---
    # topic に文字列以外を入れるケースは入れない。Python はそのまま通すが
    # （プロンプトに 123 と出る）、Go 側は文字列で受けるので表現できない。
    # クライアントはそもそも topic を送らないので実入力には現れない。
    param_cases = [
        {},
        {"topic": "食べ物"},
        {"topic": ""},
        {"topic": None},
        {"topic": "  食べ物  "},
        {"timeFrame": "いま起きていること"},
        {"timeFrame": ""},
        {"relation": "自分より目上／顔見知り程度"},
        {"relation": ""},
        {"topic": "食べ物", "timeFrame": "これからのこと",
         "relation": "自分と対等／家族や恋人のように近い"},
        {"unknown": "x"},
    ]
    passthrough = []
    for params in param_cases:
        r = prompts.resolve_generation_params(
            dict(params), is_premium=True, target_words=None, estimated_vocab=1000
        )
        passthrough.append({
            "params": params,
            "topic": r["topic"],
            # 未指定なら抽選値。候補に入っていることだけ確かめる。
            "time_frame": r["timeFrame"],
            "time_frame_given": bool(params.get("timeFrame")),
            "relation": r["relation"],
            "relation_given": bool(params.get("relation")),
            "sub_theme": r["subTheme"],
        })
    out["params"] = passthrough

    # --- 抽選の候補集合 ---
    out["time_frames"] = prompts.TIME_FRAMES
    out["relation_statuses"] = prompts.RELATION_STATUSES
    out["relation_intimacy"] = prompts.RELATION_INTIMACY
    out["relation_separator"] = "／"

    # --- サブテーマを持つテーマ ---
    out["topic_sub_themes"] = {
        k: v for k, v in prompts.TOPIC_SUB_THEMES.items()
    }

    path = os.path.join(os.path.dirname(__file__), "resolve_golden.json")
    with open(path, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False)
    print("wrote", path)
    for k, v in out.items():
        print(f"  {k}: {len(v)}")


if __name__ == "__main__":
    main()
