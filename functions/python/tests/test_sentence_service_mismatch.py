"""thai_text と word_breakdown の綴り不一致で1回だけ作り直すテスト。"""

from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import sentence_service


def _sentence(thai: str, words: list[str]) -> dict:
    return {
        "thai_text": thai,
        "japanese_translation": "x",
        "word_breakdown": [{"word": w, "meaning": "x"} for w in words],
        "context": "daily",
    }


def test_mismatch_triggers_one_regeneration(monkeypatch):
    prompts: list[str] = []
    # 1回目は綴りが食い違う（ที vs มี）、2回目は揃っている
    responses = [
        _sentence("ไม่ทีที่ไหนขายสีนี้เลย", ["ไม่", "มี", "ที่ไหน", "ขาย", "สี", "นี้", "เลย"]),
        _sentence("ไม่มีที่ไหนขายสีนี้เลย", ["ไม่", "มี", "ที่ไหน", "ขาย", "สี", "นี้", "เลย"]),
    ]

    def fake_llm(system_prompt, user_prompt, is_premium, tier_label, schema=None):
        prompts.append(user_prompt)
        return responses[len(prompts) - 1]

    monkeypatch.setattr(sentence_service, "_prewarm_nlp_async", lambda: None)
    monkeypatch.setattr(sentence_service, "_llm_generate_sync", fake_llm)
    monkeypatch.setattr(sentence_service, "_enrich_with_nlp", lambda s, lang="ja": None)

    result = sentence_service._generate_single(
        "system", "prompt", False, "free", target_words=None
    )

    assert len(prompts) == 2
    assert "再生成指示" in prompts[1]
    assert result["thai_text"] == "ไม่มีที่ไหนขายสีนี้เลย"


def test_no_regeneration_when_breakdown_matches(monkeypatch):
    calls = {"n": 0}

    def fake_llm(system_prompt, user_prompt, is_premium, tier_label, schema=None):
        calls["n"] += 1
        return _sentence("ไม่มีที่ไหนขาย", ["ไม่", "มี", "ที่ไหน", "ขาย"])

    monkeypatch.setattr(sentence_service, "_prewarm_nlp_async", lambda: None)
    monkeypatch.setattr(sentence_service, "_llm_generate_sync", fake_llm)
    monkeypatch.setattr(sentence_service, "_enrich_with_nlp", lambda s, lang="ja": None)

    sentence_service._generate_single("system", "prompt", False, "free")

    assert calls["n"] == 1
