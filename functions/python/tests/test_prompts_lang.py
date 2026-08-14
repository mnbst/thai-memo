"""訳文言語（lang）による分岐のテスト。

最重要は「ja のプロンプトが1文字も変わっていないこと」。en 対応で共通部分を
テンプレート化したため、ja 側の文字列が意図せず動くと本番の出力が変わる。
"""

from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import prompts
from constants import (
    RESPONSE_JSON_SCHEMA,
    STYLE_LABELS_EN,
    STYLES,
    SUB_THEME_LABELS_EN,
    TIME_FRAME_LABELS_EN,
    TIME_FRAMES,
    TOPIC_LABELS_EN,
    TOPIC_SUB_THEMES,
    TOPICS,
    build_response_schema,
    localize_context,
)
from nlp import localize_pos


# ---- ja が変わっていないこと ----


def test_ja_system_prompts_have_expected_translation_lines() -> None:
    """ja のプロンプトの訳文行が既存の文言のままであること。

    free と premium で助詞の前の空白が1文字違う。共通化して揃えてしまうと
    ja の出力が動くので、その差もそのまま保つ。
    """
    assert (
        "- japanese_translationは日本語で書く。タイ語をそのまま入れない。"
        "「。」「？」「！」のどれかで終える" in prompts.SYSTEM_PROMPT_FREE
    )
    assert (
        "- japanese_translation は日本語で書く。タイ語をそのまま入れない。"
        "「。」「？」「！」のどれかで終える" in prompts.SYSTEM_PROMPT_PREMIUM
    )
    assert "meaningは日本語のみ" in prompts.SYSTEM_PROMPT_FREE
    assert "- target_notes: ターゲット単語のみ。用法・類語との違い" in (
        prompts.SYSTEM_PROMPT_PREMIUM
    )
    assert (
        "- target_notesにはターゲット単語だけを入れ、用法・類語との違いを50文字以内で記述"
        in prompts.SYSTEM_PROMPT_FREE
    )


def test_ja_is_the_default_everywhere() -> None:
    """lang を指定しない呼び出しは ja（旧クライアント・既存コードの経路）。"""
    assert prompts.get_system_prompt(True) == prompts.SYSTEM_PROMPT_PREMIUM
    assert prompts.get_system_prompt(False) == prompts.SYSTEM_PROMPT_FREE
    assert prompts.get_system_prompt(True, lang="ja") == prompts.SYSTEM_PROMPT_PREMIUM
    # ja はモジュール定数をそのまま返す（プロンプトキャッシュの prefix を壊さない）
    assert prompts.get_system_prompt(True) is prompts.SYSTEM_PROMPT_PREMIUM
    assert build_response_schema() is RESPONSE_JSON_SCHEMA


def test_ja_prompt_has_no_english_instructions() -> None:
    """en 用の指示が ja 側へ漏れていないこと。"""
    for text in (prompts.SYSTEM_PROMPT_FREE, prompts.SYSTEM_PROMPT_PREMIUM):
        assert "they/them" not in text
        assert "英語で書く" not in text


# ---- en 側 ----


def test_en_system_prompt_forbids_japanese_in_the_translation_field() -> None:
    """フィールド名が japanese_translation なので、正面から否定しておく。"""
    for is_premium in (True, False):
        text = prompts.get_system_prompt(is_premium, lang="en")
        assert "japanese_translation は英語で書く" in text
        assert "フィールド名に japanese とあるが日本語を入れない" in text


def test_en_translation_steps_cover_the_thai_side_phenomena() -> None:
    """タイ語側の現象（丁寧さ標識・親族名称の人称用法）への対処が入っていること。"""
    steps = prompts.TRANSLATION_STEPS["en"]
    assert "ครับ/ค่ะ" in steps  # 訳出しない
    assert "they/them" in steps  # 性別を決めない
    assert "you で訳す" in steps  # พี่/น้อง が話し相手のとき


def test_en_translation_steps_are_not_a_translation_of_the_ja_steps() -> None:
    """日本語ルールの英訳移植になっていないこと（設計 §3.2）。

    日本語固有の対処（カタカナ・敬体/常体・二人称の省略）は英語に持ち込まない。
    """
    steps = prompts.TRANSLATION_STEPS["en"]
    assert "カタカナ" not in steps
    assert "丁寧体" not in steps
    assert "「ねえ」" not in steps


def test_register_constraint_switches_translation_steps() -> None:
    ja = prompts.build_register_constraint("", None, lang="ja")
    en = prompts.build_register_constraint("", None, lang="en")

    assert prompts.JA_TRANSLATION_STEPS in ja
    assert prompts.EN_TRANSLATION_STEPS in en
    assert prompts.JA_TRANSLATION_STEPS not in en
    # 訳語のレジスタは言語ごと。ja の項が en に混ざらない
    assert "×「再び」→○「また」" in ja
    assert "×「再び」→○「また」" not in en
    # タイ語の構文ルールは言語非依存。両方に入る
    assert "สามารถ〜ได้ は使わない" in ja
    assert "สามารถ〜ได้ は使わない" in en


def test_en_schema_descriptions_demand_english() -> None:
    schema = build_response_schema(lang="en")
    props = schema["properties"]

    assert "必ず英語" in props["japanese_translation"]["description"]
    assert "英語" in props["word_breakdown"]["items"]["properties"]["meaning"][
        "description"
    ]
    # 構造は変えない。フィールド名は japanese_translation のまま
    assert schema["required"] == RESPONSE_JSON_SCHEMA["required"]


def test_en_schema_localizes_the_context_fields() -> None:
    """context は詳細画面にそのまま出る。訳し忘れると英語UIに日本語が残る。"""
    context = build_response_schema(lang="en")["properties"]["context"]["properties"]

    assert "英語で" in context["usage_scenarios"]["description"]
    assert "英語で" in context["cultural_notes"]["description"]


def test_en_schema_keeps_the_identifier_fields_in_japanese() -> None:
    """テーマ・文体は履歴画面の集計キー。日本語のまま返させ、表示だけ訳す。

    ここを英語にすると、サーバーがテーマを決めた回（日本語）と LLM が選んだ回
    （英語）で同じ項目の言語が混ざる。
    """
    context = build_response_schema(("topic", "style", "emotion"), lang="en")[
        "properties"
    ]["context"]["properties"]

    assert context["style"]["enum"] == STYLES
    assert context["style"]["description"] == "実際に書いた文体を最も近いものに分類する"
    assert context["topic"]["description"] == "テーマ（例: あいさつ）"
    # 自由記述でそのまま表示される emotion だけ英語
    assert "英語で" in context["emotion"]["description"]


def test_en_schema_does_not_mutate_the_shared_constant() -> None:
    build_response_schema(lang="en")
    assert RESPONSE_JSON_SCHEMA["properties"]["japanese_translation"][
        "description"
    ] == "例文の日本語訳"


# ---- 品詞ラベル ----


def test_localize_pos() -> None:
    assert localize_pos("動詞", "ja") == "動詞"
    assert localize_pos("動詞", "en") == "verb"
    assert localize_pos("類別詞", "en") == "classifier"
    # 未知のラベルは落とさずそのまま返す
    assert localize_pos("未知", "en") == "未知"


# ---- 軸ラベル（context.topic / subTheme / timeFrame / style）----


def test_localize_context_translates_server_decided_axes() -> None:
    context = {
        "topic": TOPICS[2],
        "subTheme": "道案内",
        "timeFrame": TIME_FRAMES[0],
        "style": STYLES[1],
        "emotion": "neutral",
        "cultural_notes": "Tour groups are common.",
    }

    localized = localize_context(context, "en")

    assert localized["topic"].startswith("Travel")
    assert localized["subTheme"] == "directions"
    assert localized["timeFrame"] == "Happening right now"
    assert localized["style"].startswith("Casual spoken style")
    # LLM が書いた自由記述は触らない
    assert localized["emotion"] == "neutral"
    assert localized["cultural_notes"] == "Tour groups are common."
    # 元の dict は壊さない（バンクはプロセス内でキャッシュされる）
    assert context["topic"] == TOPICS[2]


def test_localize_context_keeps_japanese_for_ja() -> None:
    context = {"topic": TOPICS[2], "subTheme": "道案内"}

    assert localize_context(context, "ja") == context


def test_localize_context_is_idempotent_and_passes_unknown_through() -> None:
    """英語化済みのバンク文にもう一度かけても壊れない。未知の値も落とさない。"""
    once = localize_context({"topic": TOPICS[2], "subTheme": "道案内"}, "en")

    assert localize_context(once, "en") == once
    assert localize_context({"topic": "未知のテーマ"}, "en") == {"topic": "未知のテーマ"}
    assert localize_context(None, "en") is None


def test_sub_theme_translation_depends_on_topic() -> None:
    """同じ「別れ」でも、あいさつは farewell、恋愛は breakup。"""
    greeting = localize_context({"topic": TOPICS[0], "subTheme": "別れ"}, "en")
    romance = localize_context({"topic": TOPICS[14], "subTheme": "別れ"}, "en")

    assert greeting["subTheme"] == "saying goodbye"
    assert romance["subTheme"] == "breaking up"


def test_every_server_decided_axis_value_has_an_english_label() -> None:
    """定数を足したら英語ラベルも足す。抜けるとその軸だけ日本語で表示される。"""
    assert set(TOPIC_LABELS_EN) == set(TOPICS)
    assert set(STYLE_LABELS_EN) == set(STYLES)
    assert set(TIME_FRAME_LABELS_EN) == set(TIME_FRAMES)
    for topic, sub_themes in TOPIC_SUB_THEMES.items():
        assert set(SUB_THEME_LABELS_EN[topic]) == set(sub_themes), topic


def test_localize_context_handles_llm_shortened_topic() -> None:
    """サーバーがテーマを決めなかった回は LLM が短縮形で書く（「食べ物」）。"""
    assert localize_context({"topic": "食べ物"}, "en")["topic"].startswith("Food")
    assert localize_context({"topic": "旅行"}, "en")["topic"].startswith("Travel")
