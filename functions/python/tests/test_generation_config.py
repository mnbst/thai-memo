"""_make_generation_config のテスト。"""

import pytest
from sentence_service import _make_generation_config
from constants import GEMINI_MODEL, GEMINI_MODEL_PREMIUM, API_TEMPERATURE, API_MAX_TOKENS


class TestMakeGenerationConfig:
    @pytest.mark.parametrize("model", [GEMINI_MODEL, GEMINI_MODEL_PREMIUM])
    def test_common_params(self, model):
        config = _make_generation_config(model)
        assert config.temperature == API_TEMPERATURE
        assert config.max_output_tokens == API_MAX_TOKENS
        assert config.response_mime_type == "application/json"

    @pytest.mark.parametrize("model", [GEMINI_MODEL, GEMINI_MODEL_PREMIUM])
    def test_no_thinking_config(self, model):
        """thinking_config はデフォルト（未設定）のまま。"""
        config = _make_generation_config(model)
        assert config.thinking_config is None
