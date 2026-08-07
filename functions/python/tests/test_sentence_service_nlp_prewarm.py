import sentence_service
import pytest
from prompts import SYSTEM_PROMPT_FREE


def test_generate_single_starts_nlp_prewarm_before_llm(monkeypatch):
    events: list[str] = []
    captured: dict[str, str] = {}

    def fake_prewarm() -> None:
        events.append("prewarm")

    def fake_llm(system_prompt, user_prompt, is_premium, tier_label, schema=None):
        events.append("llm")
        captured["system_prompt"] = system_prompt
        return {
            "thai_text": "ฉันกินข้าว",
            "japanese_translation": "私はご飯を食べます。",
            "word_breakdown": [
                {"word": "ฉัน", "meaning": "私"},
                {"word": "กิน", "meaning": "食べる"},
                {"word": "ข้าว", "meaning": "ご飯"},
            ],
            "context": "daily",
        }

    def fake_get_enrich_with_nlp():
        def enrich(sentence: dict, lang: str = "ja") -> dict:
            events.append("nlp")
            return sentence

        return enrich

    monkeypatch.setattr(sentence_service, "_prewarm_nlp_async", fake_prewarm)
    monkeypatch.setattr(sentence_service, "_llm_generate_sync", fake_llm)
    monkeypatch.setattr(
        sentence_service,
        "_get_enrich_with_nlp",
        fake_get_enrich_with_nlp,
    )

    result = sentence_service._generate_single(
        SYSTEM_PROMPT_FREE,
        "prompt",
        False,
        "free",
        target_words=["กิน"],
    )

    assert result["thai_text"] == "ฉันกินข้าว"
    assert events == ["prewarm", "llm", "nlp"]
    assert captured["system_prompt"] == SYSTEM_PROMPT_FREE


def test_generate_single_raises_when_target_missing_after_retries(monkeypatch):
    calls = 0

    def fake_prewarm() -> None:
        return None

    def fake_llm(system_prompt, user_prompt, is_premium, tier_label, schema=None):
        nonlocal calls
        calls += 1
        return {
            "thai_text": "นี่คืออะไรกันนะ",
            "japanese_translation": "これ、何だろうね？",
            "word_breakdown": [
                {"word": "นี่", "meaning": "これ"},
                {"word": "คือ", "meaning": "〜である"},
                {"word": "อะไร", "meaning": "何"},
                {"word": "กัน", "meaning": "一緒に"},
                {"word": "นะ", "meaning": "〜ね"},
            ],
        }

    def fake_get_enrich_with_nlp():
        return lambda sentence, lang="ja": sentence

    monkeypatch.setattr(sentence_service, "_prewarm_nlp_async", fake_prewarm)
    monkeypatch.setattr(sentence_service, "_llm_generate_sync", fake_llm)
    monkeypatch.setattr(
        sentence_service,
        "_get_enrich_with_nlp",
        fake_get_enrich_with_nlp,
    )

    with pytest.raises(RuntimeError, match="target words missing after retries"):
        sentence_service._generate_single(
            SYSTEM_PROMPT_FREE,
            "prompt",
            False,
            "free",
            target_words=["นี้"],
        )

    assert calls == sentence_service.MAX_RETRY + 1
