from pathlib import Path
import sys
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from constants import (
    TIME_FRAMES,
    TOPIC_SUB_THEMES,
    TOPICS,
)
import prompts
from prompts import (
    INTRO_TOPICS,
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
    # politeness は 2026-08-07 に廃止。明示指定しても無視される。
    params = {"topic": "custom-topic", "politeness": "custom-politeness"}

    result = resolve_generation_params(params, is_premium=True)
    assert result.pop("subTheme") is None
    result.pop("topicOptions")
    # 時間軸は明示指定が無ければ抽選される（値は非決定的）
    assert result.pop("timeFrame") in TIME_FRAMES
    assert result == {"topic": "custom-topic"}


def test_resolve_generation_params_uses_free_pools_and_omits_grammar() -> None:
    with (
        patch("prompts.random.choice", side_effect=lambda values: values[0]),
    ):
        resolved = resolve_generation_params({}, is_premium=False)

    assert resolved.pop("subTheme") is None
    # 2026-08-14: free 専用プールを廃止。候補は premium と同じゲート済み TOPICS。
    assert resolved.pop("topicOptions") == gate_topics_for_vocab(list(TOPICS), 0)
    assert resolved == {
        # テーマは埋めず LLM に委ねる（候補は topicOptions で渡す）
        "topic": "",
        "timeFrame": TIME_FRAMES[0],
    }


def test_time_frame_is_topic_independent() -> None:
    """時間軸はテーマで候補が変わらない（どのテーマでも全値が出る）。"""
    seen: set[str] = set()
    for topic in (TOPICS[3], TOPICS[4], TOPICS[8]):  # 仕事 / 家族 / 天気
        for _ in range(200):
            seen.add(resolve_generation_params({"topic": topic}, is_premium=True)["timeFrame"])

    assert seen == set(TIME_FRAMES)


def test_free_topic_pool_is_vocab_gated_like_premium() -> None:
    """2026-08-14: free 専用プール（FREE_TOPICS）を廃止した。

    クライアントはテーマを送らず free/premium ともサーバーが自動選出するので、
    tier でプールを分けても選択肢の差にならない。free の4件プールは
    テーマの偏りを強めるだけだった（find_best_topic 併用で BLドラマ 82.7%）。
    """
    for is_premium in (True, False):
        resolved = resolve_generation_params(
            {}, is_premium=is_premium, estimated_vocab=0
        )
        assert set(resolved["topicOptions"]) == set(INTRO_TOPICS)
        assert TOPICS[15] not in resolved["topicOptions"]  # BL は vocab>=100 で解禁


def test_unspecified_topic_is_left_to_the_llm() -> None:
    """テーマ未指定はサーバーで埋めず、候補だけ返す（LLM が選ぶ）。"""
    resolved = resolve_generation_params({}, is_premium=True, estimated_vocab=0)

    assert resolved["topic"] == ""
    assert resolved["topicOptions"]


def test_resolve_generation_params_picks_sub_theme_by_target_word() -> None:
    # 2026-08-07: politeness の embedding 重み付けは廃止したため、この経路で
    # 残っている embedding 依存は subTheme だけ。
    with patch("prompts.find_best_sub_theme", return_value="打ち合わせ"):
        resolved = resolve_generation_params(
            {"topic": "仕事（報告・連絡・相談、打ち合わせ、残業申請、同僚雑談）"},
            is_premium=True,
            target_words=["งาน"],
        )

    assert resolved["subTheme"] == "打ち合わせ"
    assert "politeness" not in resolved


def test_topic_gate_at_intro_limits_to_intro_topics() -> None:
    """入門では LLM に渡すテーマ候補が INTRO_TOPICS に限定される。"""
    resolved = resolve_generation_params({}, is_premium=True, estimated_vocab=99)

    topic_pool = resolved["topicOptions"]
    for topic in topic_pool:
        assert topic in INTRO_TOPICS
    assert TOPICS[14] not in topic_pool  # 恋愛・男女関係は初級から


def test_topic_gate_at_beginner_opens_daily_topics() -> None:
    """初級 (vocab=100) では日常系テーマまで解禁される。"""
    resolved = resolve_generation_params({}, is_premium=True, estimated_vocab=100)

    topic_pool = resolved["topicOptions"]
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
            "politeness": "politeness-a",
        },
        is_premium=True,
        estimated_vocab=100,
    )





def test_explicit_values_override_gates_after_common_prompt_vocab() -> None:
    """共通プロンプト帯を超えた premium では明示値を維持する。"""
    params = {"topic": TOPICS[3]}  # 仕事 (入門では本来除外)

    resolved = resolve_generation_params(params, is_premium=True, estimated_vocab=101)

    resolved.pop("subTheme")
    resolved.pop("topicOptions")
    assert resolved.pop("timeFrame") in TIME_FRAMES
    assert resolved == params


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
            "politeness": "politeness-a",
        },
        target_words=["กิน"],
        is_premium=True,
        estimated_vocab=101,
    )

    assert "- テーマ: topic-a" in prompt
    # 2026-08-07: 丁寧さは LLM に渡さない（クライアント指定でも出さない）。
    # 抽選した register を後付けしても丁寧体率が動かず（120文×2条件で 42%→44%）、
    # 実質の死にパラメータだった。
    assert "- 丁寧さ:" not in prompt


def test_build_uvm_prompt_with_target_words_includes_target_section() -> None:
    prompt = build_uvm_prompt(
        {
            "topic": "topic-a",
            "politeness": "politeness-a",
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
            "politeness": "politeness-a",
        },
        is_premium=True,
        estimated_vocab=101,
    )

    assert "thai_textの空白は最大1つ" not in prompt
    assert "タイ語練習文を1つ生成" not in prompt
    assert "thai_textの空白は最大1つ" in SYSTEM_PROMPT_FREE
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




def test_rules_banning_the_target_word_are_dropped() -> None:
    """ターゲット語を禁止しているルールは落とす。

    【最優先】必ず含めよ と同じプロンプトに置くと正面から矛盾し、LLM は
    最優先側に従う（2026-08-06 実測: key_word=สามารถ で
    ×ผู้โดยสารสามารถเช็คอินตอนนี้ใช่ไหมครับ）。
    """
    from prompts import build_register_constraint

    plain = build_register_constraint(TOPICS[2])
    assert "สามารถ〜ได้ は使わない" in plain
    assert "書き言葉の硬い語" in plain

    # 禁止語が key_word のときは、その語を禁じるルールだけが消える
    as_target = build_register_constraint(TOPICS[2], ["สามารถ"])
    assert "สามารถ〜ได้ は使わない" not in as_target
    assert "書き言葉の硬い語" in as_target

    hard_word = build_register_constraint(TOPICS[2], ["ท่าน"])
    assert "書き言葉の硬い語" not in hard_word
    assert "สามารถ〜ได้ は使わない" in hard_word

    # 無関係な語では何も落ちない
    assert build_register_constraint(TOPICS[2], ["ฝน"]) == plain


def test_banned_words_table_matches_rule_text() -> None:
    """_RULE_BANNED_WORDS のマーカーが実在のルールを指していること。

    ルール文を書き換えたときにテーブルが宙に浮くのを防ぐ。
    """
    rules = prompts._SPOKEN_REGISTER_RULES + list(prompts._ALWAYS_RULES)
    for word, marker in prompts._RULE_BANNED_WORDS.items():
        matched = [r for r in rules if marker in r]
        assert len(matched) == 1, f"{word} -> {marker}: {len(matched)}件"
        assert word in matched[0], f"{word} がルール本文に無い: {marker}"


def test_context_records_every_server_decided_axis() -> None:
    """サーバーが決めた軸は全て context に残す（あとから偏りを集計するため）。"""
    _, context = prompts.build_prompt_with_context(
        {"topic": TOPICS[11]}, ["วัด"], estimated_vocab=700
    )

    assert context["topic"] == TOPICS[11]
    assert context["subTheme"] in TOPIC_SUB_THEMES[TOPICS[11]]
    assert context["timeFrame"] in TIME_FRAMES
    # politeness はプロンプトに出さないので記録もしない
    # （生成に影響していない値を残すと偏り集計が誤る）
    assert "politeness" not in context
    # 文体・感情はサーバーが決めないので入らない（LLM が生成して返す）
    assert "style" not in context
    assert "emotion" not in context


def test_length_hint_max_never_drops_below_five_words() -> None:
    """上限指定の最小値は5単語。3語以下は文にならず key_word も機能語に埋まる
    （2026-08-21 実測）。"""
    for vocab in (0, 9, 30, 59, 100, 800, 1499):
        hint = prompts.get_difficulty(vocab)["length"]
        assert int(hint.removeprefix("〜").removesuffix("単語")) >= 5, vocab


def test_length_hint_ramps_up_through_intro_band() -> None:
    """入門帯は語彙の伸びに応じて段階的に伸ばし、vocab=100 で従来の7単語に繋ぐ。"""
    lengths = [prompts.get_difficulty(v)["length"] for v in (0, 10, 30, 60, 100)]

    assert lengths == ["〜5単語", "〜5単語", "〜5単語", "〜6単語", "〜7単語"]


def test_length_hint_above_intro_band_is_unchanged() -> None:
    """初級以上の補間は据え置き（入門帯だけを変えた）。"""
    assert prompts.get_difficulty(800)["length"] == "〜12単語"
    assert prompts.get_difficulty(1500)["length"] == "自然な長さ"


def test_intro_length_hint_reaches_prompt_text() -> None:
    """長さヒントが実際にプロンプト本文へ載る。"""
    prompt = build_uvm_prompt({}, target_words=["กิน"], estimated_vocab=0)

    assert "長さ: 〜5単語" in prompt
