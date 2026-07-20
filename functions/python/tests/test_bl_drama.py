"""BLドラマの参考セリフ選出とプロンプト断片のテスト。"""

from unittest.mock import patch

from themes.bl_drama import (
    _SHOT_CONTEXT,
    BL_DRAMA_SETTINGS,
    BL_DRAMA_SHOTS,
    build_drama_prompt_section,
    pick_drama_shot,
)


class TestShotContext:
    def test_covers_every_shot_referenced_by_scenes(self):
        referenced = {
            sid
            for setting in BL_DRAMA_SETTINGS
            for scene in setting["scenes"]
            for sid in scene["shots"]
        }
        assert referenced == set(BL_DRAMA_SHOTS)
        assert set(_SHOT_CONTEXT) == referenced

    def test_maps_shot_to_its_own_drama(self):
        assert _SHOT_CONTEXT["ob_01"]["drama"] == "Only Boo!"
        assert _SHOT_CONTEXT["cc_15"]["drama"] == "Cat for Cash"


class TestPickDramaShot:
    def test_uses_embedding_selection_when_target_word_given(self):
        with patch("embeddings.find_best_drama_shot", return_value="hk_05") as m:
            assert pick_drama_shot(["ชอบ"]) == "hk_05"
        # 全セリフを候補として渡していること（シーン内3件に絞らない）
        word, shots = m.call_args[0]
        assert word == "ชอบ"
        assert len(shots) == len(BL_DRAMA_SHOTS)

    def test_falls_back_to_random_when_embedding_unavailable(self):
        with patch("embeddings.find_best_drama_shot", return_value=None):
            assert pick_drama_shot(["ชอบ"]) in _SHOT_CONTEXT

    def test_random_without_target_words(self):
        assert pick_drama_shot(None) in _SHOT_CONTEXT


class TestBuildDramaPromptSection:
    def _section(self, shot_id: str) -> dict[str, str]:
        with patch("themes.bl_drama.pick_drama_shot", return_value=shot_id):
            return build_drama_prompt_section(["รัก"])

    def test_includes_exactly_one_reference_shot(self):
        section = self._section("pp_11")
        context = section["context"]

        assert BL_DRAMA_SHOTS["pp_11"] in context
        # 同一シーンの他のセリフは渡さない — 混成の余地を無くすため
        assert BL_DRAMA_SHOTS["pp_10"] not in context
        assert BL_DRAMA_SHOTS["pp_12"] not in context

    def test_includes_drama_context_of_the_picked_shot(self):
        context = self._section("pp_11")["context"]
        assert _SHOT_CONTEXT["pp_11"]["context"] in context
        assert _SHOT_CONTEXT["pp_11"]["scene"] in context

    def test_required_lines_present(self):
        required = self._section("ob_01")["required"]
        assert "คุณ" in required  # 人称置換の禁止
        assert required.count("\n") == 3
