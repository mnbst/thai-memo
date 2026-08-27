"""sentence_handlers.py の純粋部分と produce_sentence の制御を書き出す。

I/O 境界（Firestore・GCS・LLM）だけを差し替えて本物の関数を呼ぶ。
出力: functions/python/scripts/daily_golden/handlers_golden.json
"""

import json
import os
import sys
from datetime import datetime, timedelta, timezone

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", ".."))

import sentence_handlers as sh  # noqa: E402

OUT = os.path.join(os.path.dirname(__file__), "handlers_golden.json")

SENTENCE = {
    "thai_text": "ฉันกินข้าว",
    "pronunciation": "chǎn kin khâao",
    "japanese_translation": "私はご飯を食べる",
    "word_breakdown": [
        {"word": "ฉัน", "meaning": "私", "pronunciation": "chǎn ", "notes": ""},
        {"word": " กิน ", "meaning": " 食べる ", "pronunciation": "kin"},
        {"word": "ข้าวๆ", "meaning": "ご飯", "pronunciation": "khâao"},
    ],
    "context": {"topic": "食べ物"},
}


def params_cases():
    param_sets = [
        {},
        {"topic": "旅行"},
        {"topic": "旅行", "lang": "en", "premium_trial": True},
        {"lang": "ja"},
        {"premium_trial": False, "style": "口語体"},
        {"topic": "", "style": "口語体", "emotion": "うれしい"},
    ]
    cases = []
    for p in param_sets:
        for is_premium in [True, False]:
            cases.append(
                {
                    "params": p,
                    "is_premium": is_premium,
                    "want": sh._effective_generation_params(p, is_premium=is_premium),
                }
            )
    return cases


def capped_vocab_cases():
    cases = []
    for data in [{}, {"estimated_vocab": 0}, {"estimated_vocab": 50},
                 {"estimated_vocab": 100}, {"estimated_vocab": 101},
                 {"estimated_vocab": 5000}]:
        for is_premium in [True, False]:
            cases.append(
                {
                    "user_data": data,
                    "is_premium": is_premium,
                    "want": sh._get_capped_estimated_vocab(data, is_premium),
                }
            )
    return cases


def key_word_cases():
    key_words = ["ฉัน", "กิน", "ข้าว", "ข้าวๆ", " กิน ", "ไม่มี", ""]
    cases = []
    for kw in key_words:
        cases.append(
            {
                "key_word": kw,
                "want_pronunciation": sh._get_key_word_pronunciation(SENTENCE, kw),
                "want_meaning": sh._get_key_word_meaning(SENTENCE, kw),
            }
        )
    return cases


def sentence_doc_cases():
    cases = []
    sentences = [
        SENTENCE,
        {**SENTENCE, "word_breakdown": []},
        {k: v for k, v in SENTENCE.items() if k not in ("pronunciation", "context")},
    ]
    for s in sentences:
        for use_premium in [True, False]:
            doc = sh._build_sentence_data(s, "กิน", use_premium_spec=use_premium)
            # SERVER_TIMESTAMP は比較できないので落とす（Go 側も同じ扱い）。
            doc = {k: v for k, v in doc.items() if k != "created_at"}
            cases.append(
                {"sentence": s, "use_premium_spec": use_premium, "want": doc}
            )
    return cases


def commit_update_cases():
    cases = []
    for data in [{}, {"first_generated_at": "already"}]:
        for n in [1, 3]:
            update = sh._build_sentence_commit_update(data, n)
            cases.append(
                {
                    "user_data": data,
                    "decrement": n,
                    # Increment / SERVER_TIMESTAMP はそのまま比べられないので
                    # キーの集合と、増減値だけを固定する。
                    "want_keys": sorted(update.keys()),
                    "want_remaining_delta": -n,
                    "want_count_delta": n,
                }
            )
    return cases


def trial_cases():
    now = datetime(2026, 8, 27, 3, 0, tzinfo=timezone.utc)
    expires = [
        None,
        now - timedelta(seconds=1),
        now,
        now + timedelta(seconds=1),
        now + timedelta(days=2),
    ]
    cases = []
    for is_premium in [True, False]:
        for e in expires:
            cases.append(
                {
                    "is_premium": is_premium,
                    "expires_at": e.isoformat() if e else None,
                    "now": now.isoformat(),
                    "want": sh._resolve_trial_active(
                        is_premium=is_premium, trial_expires_at=e, now=now
                    ),
                }
            )
    return cases


def ceil_cases():
    values = [
        datetime(2026, 8, 26, 15, 0, tzinfo=timezone.utc),  # JST 0:00 ちょうど
        datetime(2026, 8, 26, 15, 0, 1, tzinfo=timezone.utc),
        datetime(2026, 8, 26, 14, 59, 59, tzinfo=timezone.utc),
        datetime(2026, 1, 1, 0, 0, tzinfo=timezone.utc),
        datetime(2025, 12, 31, 23, 59, 59, tzinfo=timezone.utc),
    ]
    return [
        {
            "value": v.isoformat(),
            "want": sh._ceil_to_jst_midnight(v).astimezone(timezone.utc).isoformat(),
        }
        for v in values
    ]


def produce_cases():
    """produce_sentence の制御（キャッシュ優先・引き直し・LLM 呼び出し）。"""
    cases = []

    scenarios = [
        # (説明, use_premium_spec, cache_only, select_retry, キャッシュのヒット順)
        ("free でキャッシュに当たる", False, False, 1, [True]),
        ("free でキャッシュに外れて LLM", False, False, 1, [False]),
        ("premium はキャッシュを見ない", True, False, 1, [True]),
        ("配信free: 1回目で当たる", False, True, 3, [True, True, True]),
        ("配信free: 3回目で当たる", False, True, 3, [False, False, True]),
        ("配信free: 全部外れて配信しない", False, True, 3, [False, False, False]),
        ("select_retry=0 は1回だけ引く", False, True, 0, [False]),
        # 通常経路（cache_only=False）は select_retry が大きくても1周で抜ける。
        ("通常free: 引き直しせず LLM へ", False, False, 3, [False, True, True]),
        ("premium: 引き直しせず LLM へ", True, False, 3, [True, True, True]),
    ]

    for name, use_premium, cache_only, retry, hits in scenarios:
      for vocab in [42, 3000]:
        calls = {"select": 0, "pick": [], "generate": []}

        def fake_select(db, uid, params, *, is_premium, estimated_vocab, count=1):
            calls["select"] += 1
            # is_premium は use_premium_prompt_for_vocab の結果。語彙スコアで
            # 変わるので、ここで捕まえておく。
            calls.setdefault("select_is_premium", []).append(is_premium)
            calls.setdefault("select_estimated_vocab", []).append(estimated_vocab)
            return ([f"w{calls['select']}"], f"topic{calls['select']}")

        def fake_pick(target_word, lang="ja", topic=""):
            calls["pick"].append(
                {"target_word": target_word, "lang": lang, "topic": topic}
            )
            i = len(calls["pick"]) - 1
            if i < len(hits) and hits[i]:
                return {**SENTENCE, "key_word": target_word}
            return None

        def fake_generate(params, is_premium, *, target_words, estimated_vocab, lang):
            calls["generate"].append(
                {
                    "topic": params.get("topic"),
                    "is_premium": is_premium,
                    "target_words": target_words,
                    "lang": lang,
                }
            )
            return {**SENTENCE}

        orig = (
            sh._select_target_words_with_topic,
            sh.pick_free_sentence,
            sh.generate_sentence,
        )
        sh._select_target_words_with_topic = fake_select
        sh.pick_free_sentence = fake_pick
        sh.generate_sentence = fake_generate
        try:
            got = sh.produce_sentence(
                None,
                "uid",
                {"topic": "指定"},
                use_premium_spec=use_premium,
                estimated_vocab=vocab,
                cache_only=cache_only,
                select_retry=retry,
                lang="ja",
            )
        finally:
            (
                sh._select_target_words_with_topic,
                sh.pick_free_sentence,
                sh.generate_sentence,
            ) = orig

        cases.append(
            {
                "name": f"{name} (vocab={vocab})",
                "estimated_vocab": vocab,
                "use_premium_spec": use_premium,
                "cache_only": cache_only,
                "select_retry": retry,
                "cache_hits": hits,
                "calls": calls,
                "want": None
                if got is None
                else {
                    "generation_tier": got[0].get("generation_tier"),
                    "from_cache": got[3],
                    "target_words": got[1],
                    "chosen_topic": got[2],
                },
            }
        )
    return cases


def main() -> None:
    out = {
        "effective_generation_params": params_cases(),
        "capped_estimated_vocab": capped_vocab_cases(),
        "key_word_lookup": key_word_cases(),
        "sentence_doc": sentence_doc_cases(),
        "commit_update": commit_update_cases(),
        "trial_active": trial_cases(),
        "ceil_jst_midnight": ceil_cases(),
        "produce": produce_cases(),
    }
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False)
    print(f"wrote {OUT}")
    for k, v in out.items():
        print(f"  {k}: {len(v)}")


if __name__ == "__main__":
    main()
