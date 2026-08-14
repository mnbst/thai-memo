from datetime import datetime, timedelta, timezone

import pytest

from constants import resolve_lang
from sentence_handlers import (
    _build_sentence_commit_update,
    _ceil_to_jst_midnight,
    _build_sentence_data,
    _effective_generation_params,
    _resolve_trial_active,
    _trial_expires_at,
)


def test_build_sentence_data_includes_key_word_pronunciation():
    sentence = {
        "thai_text": "ฉันกินข้าว",
        "pronunciation": "chǎn kin khâao",
        "japanese_translation": "私はご飯を食べます。",
        "word_breakdown": [
            {"word": "ฉัน", "pronunciation": "chǎn", "meaning": "私"},
            {"word": "กิน", "pronunciation": "kin", "meaning": "食べる"},
            {"word": "ข้าว", "pronunciation": "khâao", "meaning": "ご飯"},
        ],
    }

    sentence_data = _build_sentence_data(
        sentence,
        "ข้าว",
        use_premium_spec=False,
    )

    assert sentence_data["key_word"] == "ข้าว"
    assert sentence_data["key_word_pronunciation"] == "khâao"
    assert sentence_data["key_word_meaning"] == "ご飯"


def test_build_sentence_data_uses_empty_key_word_pronunciation_when_missing():
    sentence = {
        "thai_text": "ฉันกินข้าว",
        "pronunciation": "chǎn kin khâao",
        "japanese_translation": "私はご飯を食べます。",
        "word_breakdown": [
            {"word": "ฉัน", "pronunciation": "chǎn"},
            {"word": "กิน", "pronunciation": "kin"},
        ],
    }

    sentence_data = _build_sentence_data(
        sentence,
        "ข้าว",
        use_premium_spec=True,
    )

    assert sentence_data["key_word_pronunciation"] == ""
    assert sentence_data["key_word_meaning"] == ""


def test_effective_generation_params_removes_topic_for_free():
    params = {"topic": "タイBLドラマ", "style": "丁寧語"}

    effective = _effective_generation_params(params, is_premium=False)

    assert effective == {"style": "丁寧語"}
    assert params["topic"] == "タイBLドラマ"


def test_effective_generation_params_keeps_topic_for_premium():
    params = {"topic": "タイBLドラマ", "style": "丁寧語"}

    assert _effective_generation_params(params, is_premium=True) == params


def test_effective_generation_params_strips_premium_trial_flag():
    params = {"topic": "タイBLドラマ", "premium_trial": "true"}

    # トライアルは effective_premium=True で呼ばれ、topic は維持しフラグは除去する
    effective = _effective_generation_params(params, is_premium=True)

    assert effective == {"topic": "タイBLドラマ"}


def test_effective_generation_params_strips_lang():
    """lang は出力言語の指定であって生成条件ではない。プロンプトへ渡さない。"""
    params = {"topic": "タイBLドラマ", "lang": "en"}

    assert _effective_generation_params(params, is_premium=True) == {
        "topic": "タイBLドラマ"
    }


# ---- 言語の正規化（resolve_lang）----


@pytest.mark.parametrize(
    "data, expected",
    [
        ({"lang": "en"}, "en"),
        ({"lang": "EN"}, "en"),
        ({"lang": " ja "}, "ja"),
        # 旧クライアントは lang を送らない
        ({}, "ja"),
        (None, "ja"),
        # 未知・壊れた値は既定言語へ。英訳の誤配より無変化のほうが害が小さい
        ({"lang": "th"}, "ja"),
        ({"lang": ""}, "ja"),
        ({"lang": None}, "ja"),
        ({"lang": 123}, "ja"),
    ],
)
def test_resolve_lang(data, expected):
    assert resolve_lang(data) == expected


# ---- premium ロジック切り替え判定（_resolve_trial_active）----


_NOW = datetime(2026, 8, 7, 12, 0, tzinfo=timezone.utc)
_FUTURE = _NOW + timedelta(days=1)
_PAST = _NOW - timedelta(seconds=1)


@pytest.mark.parametrize(
    "is_premium, trial_expires_at, expected",
    [
        # 期限内なら premium と同じ扱いに切り替える
        (False, _FUTURE, True),
        # 期限切れ・期限なし（旧doc）は free のまま
        (False, _PAST, False),
        (False, None, False),
        # premium は tier 側で premium 扱い
        (True, _FUTURE, False),
    ],
)
def test_resolve_trial_active(is_premium, trial_expires_at, expected):
    assert (
        _resolve_trial_active(
            is_premium=is_premium,
            trial_expires_at=trial_expires_at,
            now=_NOW,
        )
        is expected
    )


@pytest.mark.parametrize(
    "value, expected",
    [
        (_FUTURE, _FUTURE),
        # Firestore から naive で返っても UTC として扱う
        (_FUTURE.replace(tzinfo=None), _FUTURE),
        (None, None),
        ("2026-08-07T12:00:00Z", None),
    ],
)
def test_trial_expires_at(value, expected):
    assert _trial_expires_at({"premium_trial_expires_at": value}) == expected


def test_trial_expires_at_missing_field():
    assert _trial_expires_at({}) is None


# ---- 通常クォータの消費（_build_sentence_commit_update）----


def test_commit_update_consumes_normal_quota():
    # トライアルは期間制なので、消費するのは通常クォータだけ。
    update = _build_sentence_commit_update(
        {"remaining_sentences": 5}, decrement_count=1
    )

    assert update["remaining_sentences"].value == -1
    assert update["sentence_generated_count"].value == 1
    assert "premium_trial_remaining" not in update


def test_commit_update_sets_first_generated_at_only_once():
    first = _build_sentence_commit_update(
        {"remaining_sentences": 5}, decrement_count=1
    )
    assert "first_generated_at" in first

    again = _build_sentence_commit_update(
        {"remaining_sentences": 5, "first_generated_at": "2026-01-01"},
        decrement_count=1,
    )
    assert "first_generated_at" not in again


def test_produce_sentence_free_cache_hit(monkeypatch):
    import sentence_handlers

    monkeypatch.setattr(
        sentence_handlers,
        "_select_target_words_with_topic",
        lambda db, uid, params, **kw: (["ข้าว"], "食事"),
    )
    monkeypatch.setattr(
        sentence_handlers,
        "pick_free_sentence",
        lambda word, lang="ja", topic="": {"thai_text": "ฉันกินข้าว"},
    )

    produced = sentence_handlers.produce_sentence(
        None,
        "uid",
        {},
        use_premium_spec=False,
        estimated_vocab=10,
    )

    assert produced is not None
    sentence, target_words, topic, from_cache = produced
    assert sentence["generation_tier"] == "free"
    assert target_words == ["ข้าว"]
    assert topic == "食事"
    assert from_cache is True


def test_produce_sentence_free_cache_is_looked_up_per_lang(monkeypatch):
    """free 例文バンクは言語ごと。en ユーザーには en バンクを引く。"""
    import sentence_handlers

    monkeypatch.setattr(
        sentence_handlers,
        "_select_target_words_with_topic",
        lambda db, uid, params, **kw: (["ข้าว"], "食事"),
    )

    asked = {}

    def _pick(word, lang="ja", topic=""):
        asked["lang"] = lang
        asked["topic"] = topic
        return {"thai_text": "I eat rice"}

    monkeypatch.setattr(sentence_handlers, "pick_free_sentence", _pick)

    produced = sentence_handlers.produce_sentence(
        None, "uid", {}, use_premium_spec=False, estimated_vocab=10, lang="en"
    )

    assert produced is not None
    assert asked["lang"] == "en"
    # 選出したテーマをバンク抽選にも渡す（chosenTopic と実際の文を揃える）
    assert asked["topic"] == "食事"
    assert produced[3] is True


def test_produce_sentence_falls_back_to_llm_when_bank_missing(monkeypatch):
    """その言語のバンクがまだ無ければ（空で返る）LLM 生成へ落ちる。"""
    import sentence_handlers

    monkeypatch.setattr(
        sentence_handlers,
        "_select_target_words_with_topic",
        lambda db, uid, params, **kw: (["ข้าว"], "食事"),
    )
    monkeypatch.setattr(
        sentence_handlers, "pick_free_sentence", lambda word, lang="ja", topic="": None
    )

    captured = {}

    def _generate(params, use_premium_spec, **kw):
        captured["lang"] = kw.get("lang")
        return {"thai_text": "ฉันกินข้าว"}

    monkeypatch.setattr(sentence_handlers, "generate_sentence", _generate)

    produced = sentence_handlers.produce_sentence(
        None,
        "uid",
        {},
        use_premium_spec=False,
        estimated_vocab=10,
        lang="en",
    )

    assert produced is not None
    _sentence, _words, _topic, from_cache = produced
    assert from_cache is False
    assert captured["lang"] == "en"


def test_produce_sentence_cache_only_returns_none_without_bank(monkeypatch):
    """毎日配信の free 経路（cache_only）は、その言語のバンクが無ければ配信しない。"""
    import sentence_handlers

    monkeypatch.setattr(
        sentence_handlers,
        "_select_target_words_with_topic",
        lambda db, uid, params, **kw: (["ข้าว"], "食事"),
    )
    monkeypatch.setattr(
        sentence_handlers, "pick_free_sentence", lambda word, lang="ja", topic="": None
    )

    produced = sentence_handlers.produce_sentence(
        None,
        "uid",
        {},
        use_premium_spec=False,
        estimated_vocab=10,
        cache_only=True,
        lang="en",
    )

    assert produced is None


def test_produce_sentence_cache_only_retries_then_none(monkeypatch):
    import sentence_handlers

    selected = []

    def _select(db, uid, params, **kw):
        selected.append(1)
        return ([f"word{len(selected)}"], "")

    monkeypatch.setattr(
        sentence_handlers, "_select_target_words_with_topic", _select
    )
    monkeypatch.setattr(
        sentence_handlers, "pick_free_sentence", lambda word, lang="ja", topic="": None
    )

    produced = sentence_handlers.produce_sentence(
        None,
        "uid",
        {},
        use_premium_spec=False,
        estimated_vocab=10,
        cache_only=True,
        select_retry=3,
    )

    assert produced is None
    assert len(selected) == 3


def test_produce_sentence_free_cache_miss_falls_back_to_llm(monkeypatch):
    import sentence_handlers

    monkeypatch.setattr(
        sentence_handlers,
        "_select_target_words_with_topic",
        lambda db, uid, params, **kw: (["ข้าว"], "食事"),
    )
    monkeypatch.setattr(
        sentence_handlers, "pick_free_sentence", lambda word, lang="ja", topic="": None
    )
    captured = {}

    def _generate(params, use_premium_spec, **kw):
        captured["topic"] = params.get("topic")
        return {"thai_text": "ฉันกินข้าว"}

    monkeypatch.setattr(sentence_handlers, "generate_sentence", _generate)

    produced = sentence_handlers.produce_sentence(
        None,
        "uid",
        {},
        use_premium_spec=False,
        estimated_vocab=10,
    )

    assert produced is not None
    sentence, _words, _topic, from_cache = produced
    assert from_cache is False
    assert sentence["generation_tier"] == "free"
    assert captured["topic"] == "食事"


@pytest.mark.parametrize(
    "value, expected",
    [
        # JST 14:00 → 翌 JST 0:00（= UTC 15:00）
        (datetime(2026, 8, 12, 5, 0, tzinfo=timezone.utc),
         datetime(2026, 8, 12, 15, 0, tzinfo=timezone.utc)),
        # ちょうど JST 0:00 ならそのまま
        (datetime(2026, 8, 12, 15, 0, tzinfo=timezone.utc),
         datetime(2026, 8, 12, 15, 0, tzinfo=timezone.utc)),
    ],
)
def test_ceil_to_jst_midnight(value, expected):
    assert _ceil_to_jst_midnight(value) == expected
