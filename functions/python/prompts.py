"""
「まいにちタイ語」アプリ — プロンプト構築モジュール

このファイルでは、Gemini AI に送信するプロンプト（指示文）を構築します。
無料ティアと有料ティアでプロンプトの内容が異なります。

無料ティア（build_free_prompt）:
  - 選択可能なパラメータ: トピック（4種類）、文体（2種類）のみ
  - 固定パラメータ: 丁寧さ=中立、語彙=初級、長さ=短文
  - 単語分解は最大8単語まで
  - 初心者向けのシンプルな例文を生成

有料ティア（build_premium_prompt）:
  - 全パラメータを自由に選択可能（トピック16種類、文体5種類、他多数）
  - カスタムプロンプト入力にも対応（最大20文字）
  - 単語分解は最大15単語まで
  - より複雑で多様な例文を生成
"""

import random

# 各種選択肢リストを定数モジュールからインポート
from constants import (
    EMOTIONS,  # 感情・トーン（喜び、悲しみ等）
    FREE_STYLES,  # 無料ティア用の文体サブセット
    FREE_TOPICS,  # 無料ティア用のトピックサブセット
    GRAMMAR_FOCUSES,  # 文法フォーカス（疑問文、否定文等）
    LEARNING_PURPOSES,  # 学習目的（会話練習、語彙習得等）
    POLITENESS_LEVELS,  # 丁寧さレベル（フォーマル、カジュアル等）
    SENTENCE_LENGTHS,  # 文の長さ（短文、中文、長文）
    STYLES,  # 全文体リスト
    TONE_DENSITIES,  # 声調密度（声調バリエーションの多さ）
    TOPICS,  # 全トピックリスト
    VOCAB_LEVELS,  # 語彙レベル（初級、中級、上級）
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


def build_premium_prompt(params: dict) -> str:
    """有料ティア用のプロンプトを構築する。

    有料ユーザー向けに、全パラメータをカスタマイズ可能な
    タイ語練習文を生成するプロンプトを構築する。

    パラメータが指定されない場合は、全選択肢リストからランダムに選択される。
    これにより、毎回異なる条件で多様な例文が生成される。

    Args:
        params: クライアントから渡されたパラメータ辞書。
                - "topic": トピック（省略時はランダム選択）
                - "style": 文体（省略時はランダム選択）
                - "politeness": 丁寧さレベル（省略時はランダム選択）
                - "grammarFocus": 文法フォーカス（省略時はランダム選択）
                - "vocabLevel": 語彙レベル（省略時はランダム選択）
                - "sentenceLength": 文の長さ（省略時はランダム選択）
                - "emotion": 感情・トーン（省略時はランダム選択）
                - "learningPurpose": 学習目的（省略時はランダム選択）
                - "toneDensity": 声調密度（省略時はランダム選択）
                - "customPrompt": ユーザーの追加指示（最大20文字、省略可）

    Returns:
        str: Gemini AI に送信するプロンプト文字列
    """
    # 各パラメータを取得（未指定の場合は全選択肢からランダム選択）
    topic = params.get("topic") or random.choice(TOPICS)
    style = params.get("style") or random.choice(STYLES)
    politeness = params.get("politeness") or random.choice(POLITENESS_LEVELS)
    grammar_focus = params.get("grammarFocus") or random.choice(GRAMMAR_FOCUSES)
    vocab_level = params.get("vocabLevel") or random.choice(VOCAB_LEVELS)
    sentence_length = params.get("sentenceLength") or random.choice(SENTENCE_LENGTHS)
    emotion = params.get("emotion") or random.choice(EMOTIONS)
    learning_purpose = params.get("learningPurpose") or random.choice(LEARNING_PURPOSES)
    tone_density = params.get("toneDensity") or random.choice(TONE_DENSITIES)

    # カスタムプロンプト: 悪用防止のため20文字に制限
    custom_prompt = params.get("customPrompt", "")
    if custom_prompt:
        custom_prompt = custom_prompt[:20]

    # カスタムプロンプトが指定されている場合のみ、追加セクションを構築
    custom_section = (
        f"\n- ユーザーからの追加の指示: {custom_prompt}" if custom_prompt else ""
    )

    return f"""日本語話者向けのタイ語練習文を1つ生成してください。

要件:
- トピック: {topic}
- 文体: {style}
- 丁寧さ: {politeness}
- 文法フォーカス: {grammar_focus}
- 語彙: {vocab_level}
- 長さ: {sentence_length}
- 感情・トーン: {emotion}
- 学習目的: {learning_purpose}
- 声調密度: {tone_density}
- 単語分解は最大15単語まで
- contextの各フィールドは簡潔に（各50文字以内）{custom_section}"""
