"""
「まいにちタイ語」アプリ — プロンプト構築モジュール

このファイルでは、Gemini AI に送信するプロンプト（指示文）を構築します。
無料ティアと有料ティアでプロンプトの内容が異なります。

無料ティア（build_free_prompt）:
  - 選択可能なパラメータ: トピック（4種類）、文体（2種類）のみ
  - 固定パラメータ: 丁寧さ=中立、長さ=5〜15単語
  - 単語分解は最大12単語まで
  - 初心者向けのシンプルな例文を生成

有料ティア（build_uvm_prompt）:
  - 全パラメータを自由に選択可能（トピック16種類、文体5種類、他多数）
  - カスタムプロンプト入力にも対応（最大20文字）
  - 単語分解は最大15単語まで
  - UVMターゲット単語がある場合はそれを含む例文を生成
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


def build_free_prompt(params: dict) -> str:
    """無料ティア用のプロンプトを構築する。

    無料ユーザー向けに、制限されたパラメータで初心者用のシンプルな
    タイ語練習文を生成するプロンプトを構築する。

    パラメータが指定されない場合は、無料ティア用の選択肢からランダムに選択される。

    Args:
        params: クライアントから渡されたパラメータ辞書。
                - "topic": トピック（省略時はランダム選択）
                - "style": 文体（省略時はランダム選択）

    Returns:
        str: Gemini AI に送信するプロンプト文字列
    """
    # トピックと文体を取得（未指定の場合は無料ティア用リストからランダム選択）
    topic = params.get("topic") or random.choice(FREE_TOPICS)
    style = params.get("style") or random.choice(FREE_STYLES)

    return f"""日本語話者向けの初心者用タイ語練習文を1つ生成してください。

要件:
- トピック: {topic}
- 文体: {style}
- 丁寧さ: 中立（一般的な日常表現）
- 語彙: 初級（基本的な日常語彙のみ）
- 長さ: 中文（9〜12単語）
- 単語分解は最大12単語まで
- 同じ単語が文中に複数回出現する場合は、出現順にすべてword_breakdownに含めてください
- contextの各フィールドは簡潔に（各50文字以内）
- word_breakdownのmeaningは必ず日本語で記述してください（英語不可）"""


def build_uvm_prompt(
    params: dict,
    target_words: list[str] | None = None,
    estimated_vocab: int = 0,
) -> str:
    """有料ティア用のプロンプトを構築する。

    全パラメータをカスタマイズ可能。target_wordsが指定された場合は
    それらの単語を含む例文を生成するよう指示する。
    estimated_vocabに基づいて文章の難易度を自動調整する。

    Args:
        params: クライアントから渡されたパラメータ辞書
        target_words: UVMから選定されたターゲット単語リスト（省略可）
        estimated_vocab: ユーザーの推定語彙数（デフォルト0=初級）

    Returns:
        str: Gemini AI に送信するプロンプト文字列
    """
    diff = get_difficulty(estimated_vocab)

    topic = params.get("topic") or random.choice(TOPICS)
    style = params.get("style") or random.choice(STYLES)
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
