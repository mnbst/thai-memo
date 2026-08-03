from pathlib import Path
import sys
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from constants import (
    EMOTIONS,
    FREE_STYLES,
    FREE_TOPICS,
    GRAMMAR_FOCUSES,
    POLITENESS_LEVELS,
    STYLES,
    TOPICS,
)
from prompts import (
    GRAMMAR_MIN_VOCAB,
    INTRO_TOPICS,
    STYLE_MIN_VOCAB,
    SYSTEM_PROMPT_FREE,
    SYSTEM_PROMPT_PREMIUM,
    TOPIC_MIN_VOCAB,
    build_uvm_prompt,
    gate_topics_for_vocab,
    get_system_prompt,
    resolve_generation_params,
    use_premium_prompt_for_vocab,
)


def test_resolve_generation_params_prefers_explicit_values() -> None:
    params = {
        "topic": "custom-topic",
        "style": "custom-style",
        "politeness": "custom-politeness",
        "grammarFocus": "custom-grammar",
        "emotion": "custom-emotion",
    }

    result = resolve_generation_params(params, is_premium=True)
    assert result.pop("subTheme") is None
    assert result == params


def test_resolve_generation_params_uses_free_pools_and_omits_grammar() -> None:
    with (
        patch("prompts.random.choice", side_effect=lambda values: values[0]),
        patch("prompts.get_topic_option_similarity_weights", return_value=None),
        patch(
            "prompts.random.choices",
            side_effect=lambda population, weights, k: [population[0]],
        ),
    ):
        resolved = resolve_generation_params({}, is_premium=False)

    assert resolved.pop("subTheme") is None
    assert resolved == {
        "topic": FREE_TOPICS[0],
        "style": FREE_STYLES[0],
        "politeness": "フォーマル（丁寧語・敬語を使用）",
        "grammarFocus": None,
        "emotion": "喜び・嬉しさ",
    }


def test_free_topics_exclude_travel() -> None:
    assert FREE_TOPICS == [
        TOPICS[0],
        TOPICS[1],
        TOPICS[5],
        TOPICS[15],
    ]
    assert TOPICS[2] not in FREE_TOPICS


def test_free_topic_pool_is_not_vocab_gated() -> None:
    selected_topics: list[str] = []

    def capture_choice(values):
        selected_topics.append(list(values))
        return values[-1]

    with (
        patch("prompts.get_topic_option_similarity_weights", return_value=None),
        patch("prompts.get_emotion_similarity_weights", return_value=None),
        patch("prompts.random.choice", side_effect=capture_choice),
        patch(
            "prompts.random.choices",
            side_effect=lambda population, weights, k: [population[0]],
        ),
    ):
        resolved = resolve_generation_params({}, is_premium=False, estimated_vocab=0)

    assert selected_topics[0] == FREE_TOPICS
    assert resolved["topic"] == TOPICS[15]


def test_resolve_generation_params_weights_style_by_target_words() -> None:
    def choose_highest_weight(population, weights, k):
        return [population[weights.index(max(weights))]]

    style_weights = [0.0] * len(STYLES)
    style_weights[STYLES.index(STYLES[2])] = 1.0

    def politeness_weights(topic, options, kind):
        weights = [0.0] * len(options)
        weights[options.index(POLITENESS_LEVELS[0])] = 1.0
        return weights

    with (
        patch("prompts.random.choices", side_effect=choose_highest_weight),
        patch(
            "prompts.get_style_similarity_weights",
            return_value=style_weights,
        ),
        patch(
            "prompts.get_topic_option_similarity_weights",
            side_effect=politeness_weights,
        ),
        patch("prompts.get_emotion_similarity_weights", return_value=None),
        patch("prompts.find_best_sub_theme", return_value="打ち合わせ"),
    ):
        resolved = resolve_generation_params(
            {"topic": "仕事（報告・連絡・相談、打ち合わせ、残業申請、同僚雑談）"},
            is_premium=True,
            target_words=["งาน"],
        )

    assert resolved["style"] == STYLES[2]
    assert resolved["politeness"] == "フォーマル（丁寧語・敬語を使用）"
    assert resolved["subTheme"] == "打ち合わせ"


def test_bl_drama_forces_casual_politeness() -> None:
    """BLドラマテーマでは politeness が常にカジュアルに固定される。"""
    with (
        patch("prompts.get_style_similarity_weights", return_value=None),
        patch("prompts.get_topic_option_similarity_weights", return_value=None),
        patch("prompts.get_emotion_similarity_weights", return_value=None),
        patch("prompts.find_best_sub_theme", return_value="告白"),
        patch("prompts.random.choice", side_effect=lambda values: values[0]),
        patch("prompts.random.choices", side_effect=lambda pop, weights, k: [pop[0]]),
    ):
        resolved = resolve_generation_params(
            {"topic": TOPICS[15]},
            is_premium=True,
            target_words=["รัก"],
        )

    assert resolved["politeness"] == POLITENESS_LEVELS[1]


def test_resolve_generation_params_weights_emotion_by_embedding() -> None:
    def choose_highest_weight(population, weights, k):
        return [population[weights.index(max(weights))]]

    emotion_weights = [0.0] * len(EMOTIONS)
    emotion_weights[EMOTIONS.index("期待・楽しみ")] = 1.0

    with patch("prompts.random.choices", side_effect=choose_highest_weight):
        with (
            patch("prompts.get_style_similarity_weights", return_value=None),
            patch("prompts.get_topic_option_similarity_weights", return_value=None),
            patch(
                "prompts.get_emotion_similarity_weights",
                return_value=emotion_weights,
            ),
            patch("prompts.find_best_sub_theme", return_value="ホテル"),
        ):
            resolved = resolve_generation_params(
                {"topic": "旅行（ホテル、道案内、観光地、空港、ツアー）"},
                is_premium=True,
                target_words=["ช่วย"],
            )

    assert resolved["emotion"] == "期待・楽しみ"


def test_style_gate_at_intro_opens_all_premium_styles() -> None:
    """premium では入門から全 style が自動選択候補になる。"""
    captured: dict = {}

    def capture_styles(population, weights, k):
        captured.setdefault("styles", list(population))
        return [population[0]]

    with (
        patch("prompts.get_style_similarity_weights", return_value=None),
        patch("prompts.get_topic_option_similarity_weights", return_value=None),
        patch("prompts.get_emotion_similarity_weights", return_value=None),
        patch("prompts.random.choice", side_effect=lambda values: values[0]),
        patch("prompts.random.choices", side_effect=capture_styles),
    ):
        resolve_generation_params({}, is_premium=True, estimated_vocab=0)

    assert captured["styles"] == STYLES


def test_style_gate_at_beginner_keeps_all_premium_styles() -> None:
    """premium の style 候補は語彙スコアで変化しない。"""
    captured: dict = {}

    def capture_styles(population, weights, k):
        captured.setdefault("styles", list(population))
        return [population[0]]

    with (
        patch("prompts.get_style_similarity_weights", return_value=None),
        patch("prompts.get_topic_option_similarity_weights", return_value=None),
        patch("prompts.get_emotion_similarity_weights", return_value=None),
        patch("prompts.random.choice", side_effect=lambda values: values[0]),
        patch("prompts.random.choices", side_effect=capture_styles),
    ):
        resolve_generation_params({}, is_premium=True, estimated_vocab=200)

    assert captured["styles"] == STYLES


def test_style_gate_at_pre_intermediate_opens_all() -> None:
    """初中級 (vocab=400) で全 style が解禁される。"""
    captured: dict = {}

    def capture_styles(population, weights, k):
        captured.setdefault("styles", list(population))
        return [population[0]]

    with (
        patch("prompts.get_style_similarity_weights", return_value=None),
        patch("prompts.get_topic_option_similarity_weights", return_value=None),
        patch("prompts.get_emotion_similarity_weights", return_value=None),
        patch("prompts.random.choice", side_effect=lambda values: values[0]),
        patch("prompts.random.choices", side_effect=capture_styles),
    ):
        resolve_generation_params({}, is_premium=True, estimated_vocab=400)

    for style in STYLES:
        assert style in captured["styles"]


def test_topic_gate_at_intro_limits_to_intro_topics() -> None:
    """入門では自動選択のテーマが INTRO_TOPICS に限定される。"""
    selected_topics: list[str] = []

    def capture_choice(values):
        selected_topics.append(list(values))
        return values[0]

    with (
        patch("prompts.get_topic_option_similarity_weights", return_value=None),
        patch("prompts.get_emotion_similarity_weights", return_value=None),
        patch("prompts.random.choice", side_effect=capture_choice),
        patch(
            "prompts.random.choices",
            side_effect=lambda population, weights, k: [population[0]],
        ),
    ):
        resolve_generation_params({}, is_premium=True, estimated_vocab=99)

    topic_pool = selected_topics[0]
    for topic in topic_pool:
        assert topic in INTRO_TOPICS
    assert TOPICS[14] not in topic_pool  # 恋愛・男女関係は初級から


def test_topic_gate_at_beginner_opens_daily_topics() -> None:
    """初級 (vocab=100) では日常系テーマまで解禁される。"""
    selected_topics: list[str] = []

    def capture_choice(values):
        selected_topics.append(list(values))
        return values[0]

    with (
        patch("prompts.get_topic_option_similarity_weights", return_value=None),
        patch("prompts.get_emotion_similarity_weights", return_value=None),
        patch("prompts.random.choice", side_effect=capture_choice),
        patch(
            "prompts.random.choices",
            side_effect=lambda population, weights, k: [population[0]],
        ),
    ):
        resolve_generation_params({}, is_premium=True, estimated_vocab=100)

    topic_pool = selected_topics[0]
    assert topic_pool == gate_topics_for_vocab(TOPICS, 100)
    assert TOPICS[14] in topic_pool  # 恋愛・男女関係
    assert TOPICS[10] not in topic_pool  # 学校
    assert TOPICS[11] not in topic_pool  # 宗教・信仰
    assert TOPICS[12] not in topic_pool  # 伝統・祭り
    assert TOPICS[13] not in topic_pool  # 礼儀作法


def test_topic_gate_at_pre_intermediate_adds_school() -> None:
    """初中級 (vocab=300) では学校まで解禁される。"""
    topic_pool = gate_topics_for_vocab(TOPICS, 300)

    assert TOPICS[10] in topic_pool  # 学校
    assert TOPICS[11] not in topic_pool  # 宗教・信仰
    assert TOPICS[12] not in topic_pool  # 伝統・祭り
    assert TOPICS[13] not in topic_pool  # 礼儀作法


def test_topic_gate_at_intermediate_opens_all() -> None:
    """中級 (vocab=600) で全テーマが解禁される。"""
    assert gate_topics_for_vocab(TOPICS, 600) == TOPICS


def test_premium_low_vocab_uses_premium_prompt_params() -> None:
    """語彙100以下でも premium は premium プロンプトパラメータを使う。"""
    prompt = build_uvm_prompt(
        {
            "topic": "topic-a",
            "style": "style-a",
            "politeness": "politeness-a",
            "grammarFocus": "grammar-a",
            "emotion": "emotion-a",
        },
        is_premium=True,
        estimated_vocab=100,
    )

    assert "- 文法フォーカス: grammar-a" in prompt


def test_grammar_gate_at_intermediate_includes_conditional() -> None:
    """中級 (vocab=1000) で条件文まで含む全 grammar が候補になる。"""
    captured: dict = {}

    def capture_choice(values):
        if values and values[0] in GRAMMAR_FOCUSES:
            captured["grammar_pool"] = list(values)
        return values[0]

    with (
        patch("prompts.get_topic_option_similarity_weights", return_value=None),
        patch("prompts.get_emotion_similarity_weights", return_value=None),
        patch("prompts.random.choice", side_effect=capture_choice),
        patch(
            "prompts.random.choices",
            side_effect=lambda population, weights, k: [population[0]],
        ),
    ):
        resolve_generation_params({}, is_premium=True, estimated_vocab=1000)

    assert captured["grammar_pool"] == GRAMMAR_FOCUSES


def test_explicit_values_override_gates_after_common_prompt_vocab() -> None:
    """共通プロンプト帯を超えた premium では明示値を維持する。"""
    params = {
        "topic": TOPICS[3],  # 仕事 (入門では本来除外)
        "style": STYLES[0],  # ニュース記事体
        "grammarFocus": GRAMMAR_FOCUSES[3],  # 条件文 (入門では本来除外)
        "politeness": POLITENESS_LEVELS[0],
        "emotion": EMOTIONS[0],
    }

    resolved = resolve_generation_params(params, is_premium=True, estimated_vocab=101)

    resolved.pop("subTheme")
    assert resolved == params


def test_style_min_vocab_coverage() -> None:
    """style は語彙スコアでは制限しない。"""
    assert STYLE_MIN_VOCAB == {}


def test_topic_min_vocab_coverage() -> None:
    """TOPIC_MIN_VOCAB が実データ確認後の段階解禁を満たすこと。"""
    intro_topics = [topic for topic in TOPICS if topic not in TOPIC_MIN_VOCAB]
    assert set(intro_topics) == INTRO_TOPICS

    assert TOPIC_MIN_VOCAB[TOPICS[3]] == 100  # 仕事
    assert TOPIC_MIN_VOCAB[TOPICS[6]] == 100  # 交通
    assert TOPIC_MIN_VOCAB[TOPICS[7]] == 100  # 健康
    assert TOPIC_MIN_VOCAB[TOPICS[9]] == 100  # 趣味
    assert TOPIC_MIN_VOCAB[TOPICS[14]] == 100  # 恋愛・男女関係
    assert TOPIC_MIN_VOCAB[TOPICS[10]] == 300  # 学校
    assert TOPIC_MIN_VOCAB[TOPICS[11]] == 600  # 宗教・信仰
    assert TOPIC_MIN_VOCAB[TOPICS[12]] == 600  # 伝統・祭り
    assert TOPIC_MIN_VOCAB[TOPICS[13]] == 600  # 礼儀作法


def test_build_uvm_prompt_includes_all_resolved_target_word_conditions() -> None:
    prompt = build_uvm_prompt(
        {
            "topic": "topic-a",
            "style": "style-a",
            "politeness": "politeness-a",
            "grammarFocus": "grammar-a",
            "emotion": "emotion-a",
        },
        target_words=["กิน"],
        is_premium=True,
        estimated_vocab=101,
    )

    assert "- テーマ: topic-a" in prompt
    assert "- 文体: style-a" in prompt
    assert "- 丁寧さ: politeness-a" in prompt
    assert "- 文法フォーカス: grammar-a" in prompt
    assert "- 感情・トーン: emotion-a" in prompt


def test_build_uvm_prompt_with_target_words_includes_target_section() -> None:
    prompt = build_uvm_prompt(
        {
            "topic": "topic-a",
            "style": "style-a",
            "politeness": "politeness-a",
            "grammarFocus": "grammar-a",
            "emotion": "emotion-a",
        },
        target_words=["เข"],
        is_premium=True,
    )

    assert "以下のタイ語単語を必ず含めてください" in prompt
    # 出力ルールは system prompt 側に移動しているため user prompt には含まれない
    assert "word_breakdownのmeaningは必ず日本語で記述してください" not in prompt
    assert "ผม=僕/私（男性）" not in prompt


def test_build_uvm_prompt_excludes_fixed_output_rules() -> None:
    """固定の出力ルールは system prompt に集約し、user prompt からは除かれる。"""

    prompt = build_uvm_prompt(
        {
            "topic": "topic-a",
            "style": "style-a",
            "politeness": "politeness-a",
            "grammarFocus": "grammar-a",
            "emotion": "emotion-a",
        },
        is_premium=True,
        estimated_vocab=101,
    )

    assert "分かち書き禁止" not in prompt
    assert "タイ語練習文を1つ生成" not in prompt
    assert "分かち書き禁止" in SYSTEM_PROMPT_FREE
    assert "meaningは日本語のみ" in SYSTEM_PROMPT_FREE
    assert "構文ルール" in SYSTEM_PROMPT_PREMIUM
    assert "英語的SVOを避ける" in SYSTEM_PROMPT_PREMIUM


def test_get_system_prompt_selects_tier_prompt() -> None:
    assert get_system_prompt(False) == SYSTEM_PROMPT_FREE
    assert get_system_prompt(True) == SYSTEM_PROMPT_PREMIUM


def test_premium_always_uses_premium_prompt() -> None:
    assert use_premium_prompt_for_vocab(True, 0) is True
    assert use_premium_prompt_for_vocab(True, 100) is True
    assert use_premium_prompt_for_vocab(False, 200) is False
    assert get_system_prompt(True, estimated_vocab=0) == SYSTEM_PROMPT_PREMIUM
    assert get_system_prompt(True, estimated_vocab=100) == SYSTEM_PROMPT_PREMIUM
    assert get_system_prompt(False, estimated_vocab=200) == SYSTEM_PROMPT_FREE


def test_build_uvm_prompt_includes_grammar_focus_without_target_words() -> None:
    prompt = build_uvm_prompt(
        {
            "topic": "topic-a",
            "style": "style-a",
            "politeness": "politeness-a",
            "grammarFocus": "grammar-a",
            "emotion": "emotion-a",
        },
        is_premium=True,
        estimated_vocab=101,
    )

    assert "- 文法フォーカス: grammar-a" in prompt
