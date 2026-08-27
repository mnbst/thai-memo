"""ターゲット語選定の前段（テーマの決定）の golden を作る。

対象:
  - sentence_service.select_uvm_target_words の前半（テーマ候補プールと
    free の一様抽選）
  - sentence_service.resolve_interview_topic

抽選そのものは乱数列が Go と違うので、random.random / random.choice を
台本に差し替えて決定的にする。Go 側も同じ台本を注入して比べる。

出力: functions/python/scripts/daily_golden/select_golden.json
"""

import json
import os
import random
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", ".."))

import constants as c  # noqa: E402
import sentence_service as ss  # noqa: E402

OUT = os.path.join(os.path.dirname(__file__), "select_golden.json")


class Script:
    """random.random / random.choice を台本で置き換える。

    choice は「候補列の何番目を引くか」を記録する（Go には添字で渡す）。
    """

    def __init__(self, rand_value, choice_index):
        self.rand_value = rand_value
        self.choice_index = choice_index
        self.choice_calls = 0

    def random(self):
        return self.rand_value

    def choice(self, seq):
        self.choice_calls += 1
        return seq[self.choice_index % len(seq)]


def choose_topic_cases():
    """本物の select_uvm_target_words を呼び、get_session_words に渡る
    topic / topics_pool を捕まえる。前半のロジックを写経すると移植ミスを
    検出できないので、I/O 境界（Firestore・GCS）だけを差し替える。"""
    captured = {}

    def fake_get_session_words(db, uid, freq_rank, **kwargs):
        captured["topic"] = kwargs.get("topic")
        captured["topics_pool"] = kwargs.get("topics_pool")
        return [], ""

    orig_gsw = ss.get_session_words
    orig_freq = ss.get_freq_rank
    ss.get_session_words = fake_get_session_words
    ss.get_freq_rank = lambda: {}

    cases = []
    vocabs = [0, 50, 100, 300, 800, 2000]
    rand_values = [0.0, 0.05, 0.0999, 0.1, 0.5, 0.99]
    try:
        for topic in ["", "食べ物（注文、感想、屋台、辛さ調整、アレルギー）"]:
            for is_premium in [True, False]:
                for vocab in vocabs:
                    for rv in rand_values:
                        for ci in [0, 1, 3, 14, 15, 16, 20]:
                            script = Script(rv, ci)
                            orig_random, orig_choice = random.random, random.choice
                            random.random, random.choice = script.random, script.choice
                            captured.clear()
                            try:
                                ss.select_uvm_target_words(
                                    None,
                                    "uid",
                                    {"topic": topic} if topic else {},
                                    is_premium=is_premium,
                                    estimated_vocab=vocab,
                                )
                            finally:
                                random.random, random.choice = orig_random, orig_choice
                            cases.append(
                                {
                                    "topic": topic,
                                    "is_premium": is_premium,
                                    "estimated_vocab": vocab,
                                    "rand_value": rv,
                                    "choice_index": ci,
                                    "want_topic": captured["topic"],
                                    "want_pool": captured["topics_pool"],
                                }
                            )
    finally:
        ss.get_session_words = orig_gsw
        ss.get_freq_rank = orig_freq
    return cases


def interview_cases():
    user_datas = [
        {},
        {"interview": None},
        {"interview": "travel"},
        {"interview": {}},
        {"interview": {"goal": None}},
        {"interview": {"goal": "unknown"}},
        {"interview": {"goal": "travel"}},
        {"interview": {"goal": "work"}},
        {"interview": {"goal": "live"}},
        {"interview": {"goal": "culture"}},
    ]
    cases = []
    for ud in user_datas:
        for ci in [0, 1, 2, 5]:
            script = Script(0.0, ci)
            orig_choice = random.choice
            random.choice = script.choice
            try:
                got = ss.resolve_interview_topic(ud)
            finally:
                random.choice = orig_choice
            cases.append(
                {"user_data": ud, "choice_index": ci, "want": got}
            )
    return cases


def main() -> None:
    out = {
        "choose_topic": choose_topic_cases(),
        "resolve_interview_topic": interview_cases(),
    }
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False)
    print(f"wrote {OUT}")
    for k, v in out.items():
        print(f"  {k}: {len(v)}")


if __name__ == "__main__":
    main()
