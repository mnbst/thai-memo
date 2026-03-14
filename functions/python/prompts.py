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
- contextの各フィールドは簡潔に（各50文字以内）"""


def build_uvm_prompt(params: dict, target_words: list[str] | None = None) -> str:
    """有料ティア用のプロンプトを構築する。

    全パラメータをカスタマイズ可能。target_wordsが指定された場合は
    それらの単語を含む例文を生成するよう指示する。

    Args:
        params: クライアントから渡されたパラメータ辞書
        target_words: UVMから選定されたターゲット単語リスト（省略可）

    Returns:
        str: Gemini AI に送信するプロンプト文字列
    """
    topic = params.get("topic") or random.choice(TOPICS)
    style = params.get("style") or random.choice(STYLES)
    politeness = params.get("politeness") or random.choice(POLITENESS_LEVELS)
    grammar_focus = params.get("grammarFocus") or random.choice(GRAMMAR_FOCUSES)
    emotion = params.get("emotion") or random.choice(EMOTIONS)

    custom_prompt = params.get("customPrompt", "")
    if custom_prompt:
        custom_prompt = custom_prompt[:20]
    custom_section = (
        f"\n- ユーザーからの追加の指示: {custom_prompt}" if custom_prompt else ""
    )

    target_section = ""
    if target_words:
        words_str = ", ".join(target_words)
        target_section = f"""
【重要】以下のタイ語単語を含む例文にしてください:
{words_str}
"""

    return f"""日本語話者向けのタイ語練習文を1つ生成してください。
{target_section}
要件:
- トピック: {topic}
- 文体: {style}
- 丁寧さ: {politeness}
- 文法フォーカス: {grammar_focus}
- 感情・トーン: {emotion}
- 長さ: 5〜15単語の範囲で、トピックと文体に合った自然な長さにしてください
- 単語分解は最大15単語まで
- contextの各フィールドは簡潔に（各50文字以内）{custom_section}"""
