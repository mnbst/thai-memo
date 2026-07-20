"""省トークン応答フォーマットの後方互換変換テスト。"""

from unittest.mock import patch

from constants import RESPONSE_JSON_SCHEMA, build_response_schema
from prompts import build_prompt_with_context
from sentence_service import _apply_response_compat, _schema_for


def _sentence() -> dict:
    return {
        "thai_text": "ฉันกินข้าว",
        "japanese_translation": "私はごはんを食べる",
        "word_breakdown": [
            {"word": "ฉัน", "meaning": "私"},
            {"word": "กิน", "meaning": "食べる"},
            {"word": "ข้าว", "meaning": "ごはん"},
        ],
        "target_notes": [{"word": "กิน", "note": "口語で広く使う"}],
        "context": {"usage_scenarios": "食事の場面", "cultural_notes": ""},
    }


class TestApplyResponseCompat:
    def test_target_notes_are_expanded_into_word_breakdown(self):
        sentence = _apply_response_compat(_sentence(), None)

        notes = {w["word"]: w["notes"] for w in sentence["word_breakdown"]}
        assert notes == {"ฉัน": "", "กิน": "口語で広く使う", "ข้าว": ""}
        assert "target_notes" not in sentence

    def test_reduplicated_target_word_matches(self):
        sentence = _sentence()
        sentence["word_breakdown"][1]["word"] = "กินๆ"
        sentence = _apply_response_compat(sentence, None)

        assert sentence["word_breakdown"][1]["notes"] == "口語で広く使う"

    def test_resolved_context_is_injected_without_dropping_llm_fields(self):
        resolved = {"topic": "食べ物", "style": "口語", "emotion": "中立・平静"}
        sentence = _apply_response_compat(_sentence(), resolved)

        assert sentence["context"] == {
            "usage_scenarios": "食事の場面",
            "cultural_notes": "",
            "topic": "食べ物",
            "style": "口語",
            "emotion": "中立・平静",
        }

    def test_missing_target_notes_key_is_tolerated(self):
        sentence = _sentence()
        del sentence["target_notes"]
        sentence = _apply_response_compat(sentence, None)

        assert all(w["notes"] == "" for w in sentence["word_breakdown"])


class TestBuildPromptWithContext:
    def test_returns_resolved_context_matching_prompt(self):
        prompt, context = build_prompt_with_context(
            {"topic": "食べ物", "style": "口語", "emotion": "うれしい"},
            ["กิน"],
            estimated_vocab=200,
        )

        assert context["topic"] == "食べ物"
        assert f"- テーマ: {context['topic']}" in prompt
        assert f"- 文体: {context['style']}" in prompt
        assert f"- 感情・トーン: {context['emotion']}" in prompt

    def test_drama_topic_omits_style_and_emotion(self):
        from constants import TOPICS

        with (
            patch("prompts.get_style_similarity_weights", return_value=None),
            patch("prompts.get_topic_option_similarity_weights", return_value=None),
            patch("prompts.get_emotion_similarity_weights", return_value=None),
            patch("prompts.find_best_sub_theme", return_value="告白"),
            patch("prompts.build_drama_prompt_section",
                  return_value={"context": "", "required": ""}),
        ):
            _, context = build_prompt_with_context(
                {"topic": TOPICS[15]},
                ["รัก"],
                estimated_vocab=800,
            )

        # ドラマ回は文体・トーンをプロンプトで指定しないため確定値が無い。
        # キーごと落とし、LLM に生成させる側へ委ねる。
        assert context == {"topic": TOPICS[15]}


class TestSchemaSelection:
    """プロンプトで指定した値は確定値を使い、指定しなかった分だけ LLM に生成させる。"""

    def _context_schema(self, schema: dict) -> dict:
        return schema["properties"]["context"]

    def test_no_extra_fields_when_all_resolved(self):
        schema = _schema_for({"topic": "食べ物", "style": "口語", "emotion": "中立"})

        assert schema is RESPONSE_JSON_SCHEMA
        props = self._context_schema(schema)["properties"]
        assert "style" not in props and "emotion" not in props

    def test_unresolved_fields_are_asked_of_llm(self):
        schema = _schema_for({"topic": "タイBLドラマ"})
        context = self._context_schema(schema)

        assert "style" in context["properties"]
        assert "emotion" in context["properties"]
        assert "style" in context["required"]
        assert "emotion" in context["required"]
        # topic は確定しているので生成させない
        assert "topic" not in context["properties"]

    def test_empty_string_counts_as_unresolved(self):
        context = self._context_schema(_schema_for({"topic": "x", "style": ""}))

        assert "style" in context["properties"]

    def test_base_schema_is_not_mutated(self):
        before = len(RESPONSE_JSON_SCHEMA["properties"]["context"]["required"])
        build_response_schema(("style", "emotion"))

        assert (
            len(RESPONSE_JSON_SCHEMA["properties"]["context"]["required"]) == before
        )
