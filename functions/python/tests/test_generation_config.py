"""OpenAI Responses API payload のテスト。"""

import pytest

from constants import API_MAX_TOKENS, OPENAI_MODEL, OPENAI_MODEL_PREMIUM
from sentence_service import _make_generation_payload


class TestMakeGenerationPayload:
    @pytest.mark.parametrize("model", [OPENAI_MODEL, OPENAI_MODEL_PREMIUM])
    def test_common_params(self, model):
        payload = _make_generation_payload(model, "prompt")

        assert payload["model"] == model
        assert payload["input"] == [{"role": "user", "content": "prompt"}]
        assert payload["max_output_tokens"] == API_MAX_TOKENS
        assert payload["reasoning"]["effort"] == "low"

    @pytest.mark.parametrize("model", [OPENAI_MODEL, OPENAI_MODEL_PREMIUM])
    def test_json_schema_format(self, model):
        payload = _make_generation_payload(model, "prompt")
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
