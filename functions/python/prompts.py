"""
「まいにちタイ語」アプリ — プロンプト構築モジュール

Gemini AI に送信するプロンプト（指示文）を構築する。
free / premium ともに build_uvm_prompt を使用する。
free ティアは estimated_vocab が 300 以下にキャップされ、
パラメータの選択肢が制限される（トピック4種、文体2種のみ）。
"""

import random

from constants import (
    EMOTIONS,  # 感情・トーン（喜び、悲しみ等）
    FREE_STYLES,  # 無料ティア用の文体サブセット
    FREE_TOPICS,  # 無料ティア用のトピックサブセット
    GRAMMAR_FOCUSES,  # 文法フォーカス（疑問文、否定文等）
    POLITENESS_LEVELS,  # 丁寧さレベル（フォーマル、カジュアル等）
    STYLES,  # 全文体リスト
    TOPICS,  # 全トピックリスト
)


DIFFICULTY_LEVELS = [
    {
        "max_vocab": 300,
        "label": "初級",
        "vocab_hint": "基本的な日常語彙のみ",
        "length": "短文（5〜8単語）",
    },
    {
        "max_vocab": 1000,
        "label": "中級",
        "vocab_hint": "日常〜やや応用的な語彙",
        "length": "中文（8〜12単語）",
    },
    {
        "max_vocab": 3000,
        "label": "上級",
        "vocab_hint": "自然な表現・慣用句を含めてよい",
        "length": "10〜15単語",
    },
    {
        "max_vocab": float("inf"),
        "label": "上級+",
        "vocab_hint": "制限なし。ネイティブに近い自然な表現",
        "length": "自然な長さ",
    },
]


def get_difficulty(estimated_vocab: int) -> dict:
    """estimated_vocab から難易度レベルを返す。"""
    for level in DIFFICULTY_LEVELS:
        if estimated_vocab <= level["max_vocab"]:
            return level
    return DIFFICULTY_LEVELS[-1]


def build_uvm_prompt(
    params: dict,
    target_words: list[str] | None = None,
    estimated_vocab: int = 0,
    is_premium: bool = True,
) -> str:
    """プロンプトを構築する（free/premium 共通）。

    target_wordsが指定された場合はそれらの単語を含む例文を生成するよう指示する。
    estimated_vocabに基づいて文章の難易度を自動調整する。
    free ティアではトピック・スタイルの選択肢が制限される。

    Args:
        params: クライアントから渡されたパラメータ辞書
        target_words: UVMから選定されたターゲット単語リスト（省略可）
        estimated_vocab: ユーザーの推定語彙数（デフォルト0=初級）
        is_premium: プレミアムティアかどうか（free時はトピック・スタイルが制限される）

    Returns:
        str: Gemini AI に送信するプロンプト文字列
    """
    diff = get_difficulty(estimated_vocab)

    topics_pool = TOPICS if is_premium else FREE_TOPICS
    styles_pool = STYLES if is_premium else FREE_STYLES

    topic = params.get("topic") or random.choice(topics_pool)
    style = params.get("style") or random.choice(styles_pool)
    politeness = params.get("politeness") or random.choice(POLITENESS_LEVELS)
    grammar_focus = params.get("grammarFocus") or random.choice(GRAMMAR_FOCUSES)
    emotion = params.get("emotion") or random.choice(EMOTIONS)

    if target_words:
        words_str = ", ".join(target_words)
        return f"""日本語話者向けのタイ語練習文を1つ生成してください。

【最優先】以下のタイ語単語を必ず含めてください:
{words_str}

【必須】難易度:
- 語彙レベル: {diff["label"]}（{diff["vocab_hint"]}）
- 長さ: {diff["length"]}

【できれば反映】以下の要素を、自然なタイ語になる範囲で取り入れてください。無理に全部入れる必要はありません:
- トピック: {topic}
- 文体: {style}
- 丁寧さ: {politeness}
- 文法フォーカス: {grammar_focus}
- 感情・トーン: {emotion}

注意: 上記の単語を含めることと自然なタイ語であることを最優先し、他の要素は補助的に扱ってください。
- 単語分解は最大15単語まで
- 同じ単語が文中に複数回出現する場合は、出現順にすべてword_breakdownに含めてください
- contextの各フィールドは簡潔に（各50文字以内）
- word_breakdownのmeaningは必ず日本語で記述してください（英語不可）"""

    return f"""日本語話者向けのタイ語練習文を1つ生成してください。

要件:
- 語彙レベル: {diff["label"]}（{diff["vocab_hint"]}）
- 長さ: {diff["length"]}
- トピック: {topic}
- 文体: {style}
- 丁寧さ: {politeness}
- 文法フォーカス: {grammar_focus}
- 感情・トーン: {emotion}
- 単語分解は最大15単語まで
- 同じ単語が文中に複数回出現する場合は、出現順にすべてword_breakdownに含めてください
- contextの各フィールドは簡潔に（各50文字以内）
- word_breakdownのmeaningは必ず日本語で記述してください（英語不可）"""
