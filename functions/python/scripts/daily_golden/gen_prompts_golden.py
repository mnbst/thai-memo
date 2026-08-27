"""prompts.py の組み立て結果を Python 実装から書き出す。

抽選（時制・関係・サブテーマ）は resolve_generation_params が行うが、
組み立て（build_prompt_with_context）は確定値だけで決まる。
抽選をモンキーパッチで固定し、プロンプト全文を突き合わせられるようにする。

出力先: functions/python/scripts/daily_golden/prompts_golden.json
"""

import itertools
import json
import os
import random
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", ".."))

import constants as c  # noqa: E402
import prompts as p  # noqa: E402


def main() -> None:
    rng = random.Random(20260827)

    # --- 単体関数 ---
    difficulty_cases = []
    vocabs = sorted({
        0, 1, 59, 60, 61, 99, 100, 101, 150, 299, 300, 599, 600,
        1000, 1499, 1500, 1501, 3000, 10000,
        *(rng.randrange(0, 2000) for _ in range(200)),
    })
    for v in vocabs:
        d = p.get_difficulty(v)
        difficulty_cases.append({
            "estimated_vocab": v,
            "label": d["label"],
            "vocab_hint": d["vocab_hint"],
            "length": d["length"],
        })

    gate_cases = []
    for v in [0, 50, 99, 100, 101, 300, 1000]:
        gate_cases.append({
            "estimated_vocab": v,
            "pool": list(c.TOPICS),
            "result": p.gate_topics_for_vocab(list(c.TOPICS), v),
        })
    # 全部落ちるプール（元のプールが返る）
    gated_only = [t for t in c.TOPICS if p.TOPIC_MIN_VOCAB.get(t, 0) > 0]
    gate_cases.append({
        "estimated_vocab": 0,
        "pool": gated_only,
        "result": p.gate_topics_for_vocab(gated_only, 0),
    })

    system_prompt_cases = []
    for is_premium in (True, False):
        for lang in ("ja", "en"):
            system_prompt_cases.append({
                "is_premium": is_premium,
                "lang": lang,
                "prompt": p.get_system_prompt(is_premium, None, lang),
            })

    # --- 制約ブロック ---
    banned = list(p._RULE_BANNED_WORDS.keys())
    target_sets = [
        [], ["กิน"], ["ผม"], [banned[0]], [banned[0], "กิน"],
        ["มัน"], ["ตัว"], ["สามารถ", "ท่าน"], ["ฉัน", "นี้", "ตัว"],
    ]
    constraint_cases = []
    for topic in ["", c.TOPICS[0], c.TOPICS[14], c.TOPICS[15]]:
        for tw in target_sets:
            for lang in ("ja", "en"):
                constraint_cases.append({
                    "topic": topic, "target_words": tw, "lang": lang,
                    "register": p.build_register_constraint(topic, tw, lang=lang),
                    "free": p.build_free_constraint(tw, lang=lang),
                    "word_class": p.build_word_class_constraint(tw),
                })

    relation_cases = []
    for status in p.RELATION_STATUSES + [""]:
        for intimacy in p.RELATION_INTIMACY + [""]:
            rel = f"{status}／{intimacy}" if status or intimacy else ""
            relation_cases.append({
                "relation": rel,
                "result": p.build_relation_constraint(rel),
            })
    relation_cases.append({"relation": "区切りなし", 
                           "result": p.build_relation_constraint("区切りなし")})

    # --- プロンプト全文 ---
    # resolve_generation_params の抽選を固定して build_prompt_with_context を回す。
    prompt_cases = []
    topics_all = [""] + list(c.TOPICS)
    time_frames = [""] + list(c.TIME_FRAMES)
    relations = ["", "自分より目上／顔見知り程度", "自分と対等／家族や恋人のように近い"]

    combos = []
    for topic in topics_all:
        for tf in time_frames:
            combos.append((topic, tf))
    # 組み合わせが多いので代表 + ランダムで絞る
    for topic, tf in combos:
        for _ in range(2):
            tw = rng.choice(target_sets)
            vocab = rng.choice([0, 50, 100, 300, 800, 1500, 3000])
            is_premium = rng.random() < 0.6
            lang = rng.choice(["ja", "en"])
            relation = rng.choice(relations)
            sub_themes = p.TOPIC_SUB_THEMES.get(topic) or []
            sub_theme = rng.choice(sub_themes) if sub_themes and rng.random() < 0.7 else None

            resolved = {
                "topic": topic,
                "topicOptions": p.gate_topics_for_vocab(list(c.TOPICS), vocab),
                "subTheme": sub_theme,
                "timeFrame": tf or None,
                "relation": relation or None,
            }
            drama = {"context": "", "required": ""}
            if topic == c.TOPICS[15]:
                # ドラマ回のブロックは別モジュール。ここでは固定文字列で代用し、
                # 「渡された値がどう配置されるか」だけを見る。
                drama = {
                    "context": "  【ドラマ設定】場面ダミー  ",
                    "required": "  【必須】ドラマ要素ダミー  ",
                }

            orig_resolve = p.resolve_generation_params
            orig_drama = p.build_drama_prompt_section
            p.resolve_generation_params = lambda *a, **k: resolved
            p.build_drama_prompt_section = lambda *a, **k: drama
            try:
                prompt, context = p.build_prompt_with_context(
                    {}, tw, estimated_vocab=vocab,
                    is_premium=is_premium, lang=lang,
                )
            finally:
                p.resolve_generation_params = orig_resolve
                p.build_drama_prompt_section = orig_drama

            prompt_cases.append({
                "resolved": resolved,
                "target_words": tw,
                "estimated_vocab": vocab,
                "is_premium": is_premium,
                "lang": lang,
                "drama": drama,
                "prompt": prompt,
                "context": context,
            })

    out = os.path.join(os.path.dirname(__file__), "prompts_golden.json")
    with open(out, "w") as f:
        json.dump({
            "difficulty_cases": difficulty_cases,
            "gate_cases": gate_cases,
            "system_prompt_cases": system_prompt_cases,
            "constraint_cases": constraint_cases,
            "relation_cases": relation_cases,
            "prompt_cases": prompt_cases,
        }, f, ensure_ascii=False)
    print(
        f"wrote difficulty={len(difficulty_cases)} gate={len(gate_cases)} "
        f"system={len(system_prompt_cases)} constraint={len(constraint_cases)} "
        f"relation={len(relation_cases)} prompt={len(prompt_cases)} -> {out}",
        file=sys.stderr,
    )


main()
