import pytest

from sentence_handlers import (
    _build_sentence_commit_update,
    _build_sentence_data,
    _effective_generation_params,
    _resolve_trial_active,
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


# ---- premium ロジック切り替え判定（_resolve_trial_active）----


@pytest.mark.parametrize(
    "is_premium, trial_requested, trial_remaining, expected",
    [
        # free＋要求＋残あり → 切り替え
        (False, True, 5, True),
        (False, True, 1, True),
        # 残回数を使い切ったら free のまま
        (False, True, 0, False),
        # 要求が無ければ消費しない（自動生成等）
        (False, False, 5, False),
        # premium は tier 側で premium 扱い、トライアルは消費しない
        (True, True, 5, False),
    ],
)
def test_resolve_trial_active(
    is_premium, trial_requested, trial_remaining, expected
):
    assert (
        _resolve_trial_active(
            is_premium=is_premium,
            trial_requested=trial_requested,
            trial_remaining=trial_remaining,
        )
        is expected
    )


# ---- 通常クォータとトライアル枠の独立消費（_build_sentence_commit_update）----


def test_commit_update_consumes_normal_quota_without_trial():
    # トライアル非対象（trial_decrement=0）: 通常クォータのみ消費し trial 枠は触らない
    update = _build_sentence_commit_update(
        {"remaining_sentences": 5, "premium_trial_remaining": 5},
        decrement_count=1,
        trial_decrement=0,
    )

    assert update["remaining_sentences"].value == -1
    assert update["sentence_generated_count"].value == 1
    assert "premium_trial_remaining" not in update


def test_commit_update_consumes_trial_and_normal_independently():
    # トライアル対象: 通常クォータとトライアル枠を別々に1ずつ消費
    update = _build_sentence_commit_update(
        {"remaining_sentences": 5, "premium_trial_remaining": 5},
        decrement_count=1,
        trial_decrement=1,
    )

    assert update["remaining_sentences"].value == -1
    assert update["premium_trial_remaining"].value == -1


def test_commit_update_does_not_decrement_trial_below_zero():
    # 残回数0のトライアル枠は減算しない（通常クォータは通常どおり消費）
    update = _build_sentence_commit_update(
        {"remaining_sentences": 5, "premium_trial_remaining": 0},
        decrement_count=1,
        trial_decrement=1,
    )

    assert update["remaining_sentences"].value == -1
    assert "premium_trial_remaining" not in update


def test_commit_update_sets_first_generated_at_only_once():
    first = _build_sentence_commit_update(
        {"remaining_sentences": 5}, decrement_count=1, trial_decrement=0
    )
    assert "first_generated_at" in first

    again = _build_sentence_commit_update(
        {"remaining_sentences": 5, "first_generated_at": "2026-01-01"},
        decrement_count=1,
        trial_decrement=0,
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
        lambda word: {"thai_text": "ฉันกินข้าว"},
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
        sentence_handlers, "pick_free_sentence", lambda word: None
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
        sentence_handlers, "pick_free_sentence", lambda word: None
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
