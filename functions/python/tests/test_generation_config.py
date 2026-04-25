"""LLM プロバイダー切替 / ペイロード構築のテスト。"""

from types import SimpleNamespace

import pytest

import llm_providers
from constants import API_MAX_TOKENS, OPENAI_MODEL, OPENAI_MODEL_PREMIUM


class TestOpenAIPayload:
    @pytest.mark.parametrize("model", [OPENAI_MODEL, OPENAI_MODEL_PREMIUM])
    def test_common_params(self, model):
        payload = llm_providers._openai_payload(model, "system", "user-prompt")

        assert payload["model"] == model
        assert payload["instructions"] == "system"
        assert payload["input"] == [{"role": "user", "content": "user-prompt"}]
        assert payload["max_output_tokens"] == API_MAX_TOKENS
        assert payload["reasoning"]["effort"] == "medium"

    @pytest.mark.parametrize("model", [OPENAI_MODEL, OPENAI_MODEL_PREMIUM])
    def test_json_schema_format(self, model):
        payload = llm_providers._openai_payload(model, "system", "user-prompt")
        fmt = payload["text"]["format"]

        assert fmt["type"] == "json_schema"
        assert fmt["name"] == "thai_sentence_response"
        assert fmt["strict"] is True
        assert fmt["schema"]["required"] == [
            "thai_text",
            "japanese_translation",
            "word_breakdown",
            "context",
        ]
        word_schema = fmt["schema"]["properties"]["word_breakdown"]["items"]
        assert word_schema["required"] == ["word", "meaning", "notes"]


class TestGeminiSchema:
    def test_strips_additional_properties(self):
        schema = llm_providers._gemini_schema()

        assert "additionalProperties" not in schema
        assert "additionalProperties" not in schema["properties"]["context"]
        assert schema["required"] == [
            "thai_text",
            "japanese_translation",
            "word_breakdown",
            "context",
        ]
        word_schema = schema["properties"]["word_breakdown"]["items"]
        assert word_schema["required"] == ["word", "meaning", "notes"]


class TestGeminiTokenUsage:
    def test_flash_pricing_matches_standard_paid_rate(self):
        assert llm_providers.GEMINI_TOKEN_PRICING_PER_MILLION[
            "gemini-2.5-flash"
        ] == {"input": 0.30, "output": 2.50}

    def test_cost_includes_thinking_tokens_in_billed_output(self, capsys):
        usage = SimpleNamespace(
            prompt_token_count=1000,
            candidates_token_count=200,
            thoughts_token_count=300,
            total_token_count=None,
        )

        llm_providers._gemini_log_token_usage(
            usage, "free", "gemini-2.5-flash"
        )

        captured = capsys.readouterr().out
        assert "output=200" in captured
        assert "thoughts=300" in captured
        assert "billed_output=500" in captured
        assert "total=1500" in captured
        assert "cost=$0.001550" in captured


class TestProviderDispatch:
    def test_gemini_dispatch(self, monkeypatch):
        monkeypatch.setattr(llm_providers, "SENTENCE_PROVIDER", "gemini")
        called: list[tuple[str, str, str]] = []

        def fake_gemini(system_prompt, user_prompt, is_premium, tier_label):
            called.append(("gemini", system_prompt, user_prompt))
            return {"thai_text": "x"}

        def fake_openai(system_prompt, user_prompt, is_premium, tier_label):
            called.append(("openai", system_prompt, user_prompt))
            return {"thai_text": "y"}

        monkeypatch.setattr(llm_providers, "_gemini_generate_sync", fake_gemini)
        monkeypatch.setattr(llm_providers, "_openai_generate_sync", fake_openai)

        llm_providers.generate_sentence_sync("sys", "user", False, "free")

        assert called == [("gemini", "sys", "user")]

    def test_openai_dispatch(self, monkeypatch):
        monkeypatch.setattr(llm_providers, "SENTENCE_PROVIDER", "openai")
        called: list[tuple[str, str, str]] = []

        def fake_gemini(system_prompt, user_prompt, is_premium, tier_label):
            called.append(("gemini", system_prompt, user_prompt))
            return {"thai_text": "x"}

        def fake_openai(system_prompt, user_prompt, is_premium, tier_label):
            called.append(("openai", system_prompt, user_prompt))
            return {"thai_text": "y"}

        monkeypatch.setattr(llm_providers, "_gemini_generate_sync", fake_gemini)
        monkeypatch.setattr(llm_providers, "_openai_generate_sync", fake_openai)

        llm_providers.generate_sentence_sync("sys", "user", True, "premium")

        assert called == [("openai", "sys", "user")]
