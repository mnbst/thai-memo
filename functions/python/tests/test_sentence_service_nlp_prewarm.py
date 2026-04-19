import json

import sentence_service


def test_generate_single_starts_nlp_prewarm_before_openai(monkeypatch):
    events: list[str] = []

    def fake_prewarm() -> None:
        events.append("prewarm")

    def fake_openai(*args, **kwargs):
        events.append("openai")
        return {
            "output_text": json.dumps(
                {
                    "thai_text": "ฉันกินข้าว",
                    "japanese_translation": "私はご飯を食べます。",
                    "word_breakdown": [{"word": "กิน", "meaning": "食べる"}],
                    "context": "daily",
                }
            )
        }

    def fake_get_enrich_with_nlp():
        def enrich(sentence: dict) -> dict:
            events.append("nlp")
            return sentence

        return enrich

    monkeypatch.setattr(sentence_service, "_prewarm_nlp_async", fake_prewarm)
    monkeypatch.setattr(
        sentence_service,
        "_call_openai_with_retry_sync",
        fake_openai,
    )
    monkeypatch.setattr(
        sentence_service,
        "_get_enrich_with_nlp",
        fake_get_enrich_with_nlp,
    )

    result = sentence_service._generate_single(
        "api-key",
        "gpt-5.4-nano",
        "prompt",
        "free",
        target_words=["กิน"],
    )

    assert result["thai_text"] == "ฉันกินข้าว"
    assert events == ["prewarm", "openai", "nlp"]
