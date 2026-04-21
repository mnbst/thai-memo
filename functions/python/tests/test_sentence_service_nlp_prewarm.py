import sentence_service
from prompts import SYSTEM_PROMPT_FREE


def test_generate_single_starts_nlp_prewarm_before_llm(monkeypatch):
    events: list[str] = []
    captured: dict[str, str] = {}

    def fake_prewarm() -> None:
        events.append("prewarm")

    def fake_llm(system_prompt, user_prompt, is_premium, tier_label):
        events.append("llm")
        captured["system_prompt"] = system_prompt
        return {
            "thai_text": "ฉันกินข้าว",
            "japanese_translation": "私はご飯を食べます。",
            "word_breakdown": [{"word": "กิน", "meaning": "食べる"}],
            "context": "daily",
        }

    def fake_get_enrich_with_nlp():
        def enrich(sentence: dict) -> dict:
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
        "prompt",
        False,
        "free",
        target_words=["กิน"],
    )

    assert result["thai_text"] == "ฉันกินข้าว"
    assert events == ["prewarm", "llm", "nlp"]
    assert captured["system_prompt"] == SYSTEM_PROMPT_FREE
