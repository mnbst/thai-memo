"""free のテーマ選択が embedding ではなくゲート済みプールの一様抽選になること。

背景: テーマ embedding の重心バイアスで find_best_topic が BLドラマを
返し続けていた（free の旧4件プール＋top114語×4回の実測で 82.7%）。
free は分布を均等にする。プール自体は premium と共通（語彙ゲートのみ）。
"""

from collections import Counter
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import sentence_service
from constants import BL_TOPIC, FREE_BL_TOPIC_RATE, TOPICS
from prompts import INTRO_TOPICS, gate_topics_for_vocab


def _stub(monkeypatch):
    """get_session_words を素通しにして、渡ったテーマだけを見る。"""
    calls: list[dict] = []

    def fake_get_session_words(db, uid, freq_rank, topic, **kwargs):
        calls.append({"topic": topic, "topics_pool": kwargs.get("topics_pool")})
        return (["ไป"], topic)

    monkeypatch.setattr(sentence_service, "get_freq_rank", lambda: {"ไป": 1})
    monkeypatch.setattr(sentence_service, "get_session_words", fake_get_session_words)
    return calls


def _pick_many(monkeypatch, n=2000, estimated_vocab=0):
    picked: Counter[str] = Counter()
    for _ in range(n):
        _, topic = sentence_service.select_uvm_target_words(
            None, "uid", {}, is_premium=False, estimated_vocab=estimated_vocab
        )
        picked[topic] += 1
    return picked


def test_free_picks_uniformly_from_the_gated_pool(monkeypatch):
    calls = _stub(monkeypatch)
    picked = _pick_many(monkeypatch)
    n = sum(picked.values())

    # 入門帯の候補は INTRO_TOPICS＋別枠の BLドラマ。
    assert set(picked) == set(INTRO_TOPICS) | {BL_TOPIC}
    # 一様なら各 (1-BL率)/len。偏りの検出だけが目的なので閾値は緩く取る。
    expected = (1 - FREE_BL_TOPIC_RATE) / len(INTRO_TOPICS)
    for topic in INTRO_TOPICS:
        assert expected * 0.6 < picked[topic] / n < expected * 1.4, picked

    # embedding 選択には落とさない（topics_pool を渡さない）。
    assert all(c["topics_pool"] is None for c in calls)


def test_free_gets_bl_at_a_fixed_rate(monkeypatch):
    """BL は語彙ゲートに関係なく一定確率で出る（free の estimated_vocab は100上限）。"""
    _stub(monkeypatch)
    for estimated_vocab in (0, 100):
        picked = _pick_many(monkeypatch, estimated_vocab=estimated_vocab)
        rate = picked[BL_TOPIC] / sum(picked.values())
        assert FREE_BL_TOPIC_RATE * 0.6 < rate < FREE_BL_TOPIC_RATE * 1.4, picked


def test_free_unlocks_more_topics_with_vocab(monkeypatch):
    _stub(monkeypatch)
    picked = set(_pick_many(monkeypatch, estimated_vocab=100))

    assert picked == set(gate_topics_for_vocab(list(TOPICS), 100))


def test_explicit_topic_is_kept(monkeypatch):
    _stub(monkeypatch)
    _, topic = sentence_service.select_uvm_target_words(
        None, "uid", {"topic": "天気"}, is_premium=False, estimated_vocab=0
    )
    assert topic == "天気"


def test_premium_still_uses_embedding_pool(monkeypatch):
    calls = _stub(monkeypatch)
    sentence_service.select_uvm_target_words(
        None, "uid", {}, is_premium=True, estimated_vocab=0
    )
    assert calls[0]["topic"] == ""
    assert calls[0]["topics_pool"]  # ゲート済みプールを渡して embedding に選ばせる


def test_pick_free_sentence_prefers_the_chosen_topic(monkeypatch):
    """バンク抽選は選出テーマを優先する（無ければテーマ無視で返す）。"""
    bank = [
        {"key_word": "ไป", "thai_text": "A", "context": {"topic": "旅行"}},
        {"key_word": "ไป", "thai_text": "B", "context": {"topic": BL_TOPIC}},
    ]
    monkeypatch.setattr(sentence_service, "get_free_sentences", lambda lang="ja": bank)

    assert sentence_service.pick_free_sentence("ไป", topic=BL_TOPIC)["thai_text"] == "B"
    assert sentence_service.pick_free_sentence("ไป", topic="旅行")["thai_text"] == "A"
    # バンクに無いテーマでも配信は落とさない
    assert sentence_service.pick_free_sentence("ไป", topic="天気") is not None
    assert sentence_service.pick_free_sentence("ไม่มี", topic="旅行") is None
