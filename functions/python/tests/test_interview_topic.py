"""ヒアリング（interview.goal）からのテーマ決定。

通常生成のテーマは端末側で決めて params で渡る（sentence_provider.dart）。
ここで検証するのは、端末を経由しない毎日配信が使う resolve_interview_topic と、
サーバーが params のテーマに手を加えないこと。
"""

import random

from constants import INTERVIEW_GOAL_TOPICS, TOPICS
from sentence_handlers import _effective_generation_params
from sentence_service import resolve_interview_topic


def test_goal_maps_to_declared_topics():
    for goal, candidates in INTERVIEW_GOAL_TOPICS.items():
        picked = {
            resolve_interview_topic({"interview": {"goal": goal}}) for _ in range(50)
        }
        assert picked <= set(candidates)
        assert picked, goal


def test_multiple_candidates_are_drawn_randomly():
    random.seed(0)
    picked = {
        resolve_interview_topic({"interview": {"goal": "travel"}}) for _ in range(100)
    }
    # 候補が4つあるテーマを1つに固定しない（偏りの付け替えを防ぐ）
    assert len(picked) > 1


def test_no_interview_or_unknown_goal_falls_back_to_auto():
    assert resolve_interview_topic({}) == ""
    assert resolve_interview_topic({"interview": None}) == ""
    assert resolve_interview_topic({"interview": {}}) == ""
    assert resolve_interview_topic({"interview": {"goal": "unknown"}}) == ""


def test_candidates_exclude_topics_no_wording_promises():
    # 学校・宗教・礼儀作法はヒアリング最終画面がどの goal でも触れていない。
    # 語彙要求だけが高くなるので候補に入れない（伝統・祭りは culture の
    # 文言が名指ししているので例外）。
    excluded = {TOPICS[10], TOPICS[11], TOPICS[13]}
    for candidates in INTERVIEW_GOAL_TOPICS.values():
        for topic in candidates:
            assert topic in TOPICS
            assert topic not in excluded


def test_candidates_cover_topics_named_in_the_philosophy_screen():
    # l10n philosophy3* が名指ししているテーマは必ず出せること
    promised = {
        "travel": [TOPICS[2], TOPICS[6]],  # 旅行・交通
        "work": [TOPICS[3]],  # 仕事
        "live": [TOPICS[5], TOPICS[4]],  # 買い物・家族
        "culture": [TOPICS[15], TOPICS[12]],  # BLドラマ・伝統・祭り
    }
    for goal, topics in promised.items():
        assert set(topics) <= set(INTERVIEW_GOAL_TOPICS[goal]), goal


def test_client_topic_is_used_as_is():
    # テーマはクライアントの指定をそのまま使う（ヒアリングからの決定は端末側）。
    params = _effective_generation_params({"topic": TOPICS[12]}, is_premium=True)
    assert params["topic"] == TOPICS[12]


def test_unspecified_topic_stays_unspecified():
    # サーバーは users doc を読んでテーマを埋めない（旧 resolve_interview_topic 経路）。
    assert not _effective_generation_params({}, is_premium=True).get("topic")


def test_free_keeps_automatic_selection():
    params = _effective_generation_params({"topic": TOPICS[2]}, is_premium=False)
    assert not params.get("topic")
