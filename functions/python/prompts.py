"""
「まいにちタイ語」アプリ — プロンプト構築モジュール

OpenAI に送信するプロンプト（指示文）を構築する。
free / premium ともに build_uvm_prompt を使用する。
free ティアは estimated_vocab が 300 以下にキャップされ、
パラメータの選択肢が制限される（テーマ4種、文体2種のみ）。
"""

import random

from constants import (
    EMOTIONS,  # 感情・トーン（喜び、悲しみ等）
    FREE_STYLES,  # 無料ティア用の文体サブセット
    FREE_TOPICS,  # 無料ティア用のテーマサブセット
    GRAMMAR_FOCUSES,  # 文法フォーカス（疑問文、否定文等）
    POLITENESS_LEVELS,  # 丁寧さレベル（フォーマル、カジュアル等）
    STYLES,  # 全文体リスト
    TOPICS,  # 全テーマリスト
)
from embeddings import (
    get_emotion_similarity_weights,
    get_topic_option_similarity_weights,
)

# 文の長さ指定はレベル定義には持たせず、estimated_vocab から
# _compute_length_hint() で補間して get_difficulty() が length を追加する。
DIFFICULTY_LEVELS = [
    {
        "max_vocab": 99,
        "label": "入門",
        "vocab_hint": "超基本的な挨拶・身近な語彙のみ",
    },
    {
        "max_vocab": 299,
        "label": "初級",
        "vocab_hint": "基本的な日常語彙のみ",
    },
    {
        "max_vocab": 599,
        "label": "初中級",
        "vocab_hint": "日常語彙中心、やや応用的な表現も可",
    },
    {
        "max_vocab": 1499,
        "label": "中級",
        "vocab_hint": "日常〜応用的な語彙、自然な表現",
    },
    {
        "max_vocab": float("inf"),
        "label": "上級",
        "vocab_hint": "制限なし。慣用句・ネイティブに近い自然な表現",
    },
]

# ─── レベル別解禁ゲート（自動選択時のみ適用。明示指定は維持） ───
# 各要素に min estimated_vocab を紐づけ、ユーザーのレベルに応じて候補を絞る。
# 閾値は DIFFICULTY_LEVELS の境界と対応: 0=入門, 100=初級, 300=初中級, 600=中級
# 文体は語彙スコアでは制限しない。tier による候補制限のみ適用する。
STYLE_MIN_VOCAB: dict[str, int] = {}

TOPIC_MIN_VOCAB: dict[str, int] = {
    TOPICS[3]: 100,  # 仕事
    TOPICS[6]: 100,  # 交通
    TOPICS[7]: 100,  # 健康
    TOPICS[9]: 100,  # 趣味
    TOPICS[14]: 100,  # 恋愛・男女関係
    TOPICS[10]: 300,  # 学校
    TOPICS[11]: 600,  # 宗教・信仰
    TOPICS[12]: 600,  # 伝統・祭り
    TOPICS[13]: 600,  # 礼儀作法
}

GRAMMAR_MIN_VOCAB: dict[str, int] = {
    GRAMMAR_FOCUSES[4]: 100,  # 助詞・接続詞 (インデックス変動注意)
    GRAMMAR_FOCUSES[5]: 100,  # 比較表現
    GRAMMAR_FOCUSES[7]: 100,  # 可能表現
    GRAMMAR_FOCUSES[8]: 100,  # 過去・完了
    GRAMMAR_FOCUSES[3]: 100,  # 条件文
}

# 入門（vocab < 100）で許可するテーマ。
# 100以上の追加テーマは TOPIC_MIN_VOCAB で段階解禁する。
INTRO_TOPICS: frozenset[str] = frozenset(
    {
        TOPICS[0],  # あいさつ
        TOPICS[1],  # 食べ物
        TOPICS[2],  # 旅行
        TOPICS[4],  # 家族
        TOPICS[5],  # 買い物
        TOPICS[8],  # 天気
    }
)

_emotion_embedding_enabled = True
_style_embedding_enabled = True
_politeness_embedding_enabled = True


def _gate_pool(
    pool: list[str],
    estimated_vocab: int,
    min_vocab: dict[str, int],
) -> list[str]:
    filtered = [item for item in pool if estimated_vocab >= min_vocab.get(item, 0)]
    return filtered or pool


def _gate_topics(pool: list[str], estimated_vocab: int) -> list[str]:
    return gate_topics_for_vocab(pool, estimated_vocab)


def gate_topics_for_vocab(pool: list[str], estimated_vocab: int) -> list[str]:
    """estimated_vocab に応じて自動選択用テーマ候補を絞る。"""
    return _gate_pool(pool, estimated_vocab, TOPIC_MIN_VOCAB)


def _topic_option_weights(topic: str, options: list[str], kind: str) -> list[float]:
    global _style_embedding_enabled, _politeness_embedding_enabled
    if kind == "style" and not _style_embedding_enabled:
        return [1.0] * len(options)
    if kind == "politeness" and not _politeness_embedding_enabled:
        return [1.0] * len(options)

    try:
        weights = get_topic_option_similarity_weights(topic, options, kind)
    except Exception as exc:
        if kind == "style":
            _style_embedding_enabled = False
        elif kind == "politeness":
            _politeness_embedding_enabled = False
        print(f"{kind} embedding weights unavailable: {exc}")
        weights = None
    return weights or [1.0] * len(options)


def _emotion_weights(target_words: list[str] | None) -> list[float]:
    global _emotion_embedding_enabled
    if not _emotion_embedding_enabled:
        return [1.0] * len(EMOTIONS)

    try:
        weights = get_emotion_similarity_weights(target_words, EMOTIONS)
    except Exception as exc:
        _emotion_embedding_enabled = False
        print(f"emotion embedding weights unavailable: {exc}")
        weights = None
    return weights or [1.0] * len(EMOTIONS)


def _weighted_choice(options: list[str], weights: list[float]) -> str:
    return random.choices(options, weights=weights, k=1)[0]


def resolve_generation_params(
    params: dict,
    is_premium: bool = True,
    target_words: list[str] | None = None,
    estimated_vocab: int = 0,
) -> dict:
    """例文生成パラメータを topic と同じ方式で確定する。

    クライアント指定値を優先し、未指定ならティアに応じた候補からランダム選択する。
    style / politeness は topic、emotion は target_words の embedding で重み付けする。
    自動選択時は estimated_vocab に応じて topic/grammar の候補プールを絞る。
    """
    topics_pool = TOPICS if is_premium else FREE_TOPICS
    styles_pool = STYLES if is_premium else FREE_STYLES
    topics_pool = _gate_topics(topics_pool, estimated_vocab)
    styles_pool = _gate_pool(styles_pool, estimated_vocab, STYLE_MIN_VOCAB)

    topic = params.get("topic") or random.choice(topics_pool)
    style = params.get("style")
    if not style:
        style = _weighted_choice(
            styles_pool,
            _topic_option_weights(topic, styles_pool, "style"),
        )

    politeness = params.get("politeness")
    if not politeness:
        politeness = _weighted_choice(
            POLITENESS_LEVELS,
            _topic_option_weights(topic, POLITENESS_LEVELS, "politeness"),
        )
    grammar_focus = None
    if is_premium:
        if params.get("grammarFocus"):
            grammar_focus = params["grammarFocus"]
        else:
            grammar_pool = _gate_pool(
                GRAMMAR_FOCUSES, estimated_vocab, GRAMMAR_MIN_VOCAB
            )
            grammar_focus = random.choice(grammar_pool)
    emotion = params.get("emotion")
    if not emotion:
        emotion = _weighted_choice(EMOTIONS, _emotion_weights(target_words))

    return {
        "topic": topic,
        "style": style,
        "politeness": politeness,
        "grammarFocus": grammar_focus,
        "emotion": emotion,
    }


def _compute_length_hint(estimated_vocab: int) -> str:
    """estimated_vocab から文の長さヒントを線形補間で返す。
    100未満: 〜7単語、1500以上: 自然な長さ、その間は比例。
    """
    if estimated_vocab >= 1500:
        return "自然な長さ"
    if estimated_vocab < 100:
        return "〜7単語"
    words = round(7 + (estimated_vocab - 100) / 1400 * 9)
    return f"〜{words}単語"


def get_difficulty(estimated_vocab: int) -> dict:
    """estimated_vocab から難易度レベルを返す。"""
    for level in DIFFICULTY_LEVELS:
        if estimated_vocab <= level["max_vocab"]:
            return {**level, "length": _compute_length_hint(estimated_vocab)}
    return {**DIFFICULTY_LEVELS[-1], "length": _compute_length_hint(estimated_vocab)}


def build_uvm_prompt(
    params: dict,
    target_words: list[str] | None = None,
    estimated_vocab: int = 0,
    is_premium: bool = True,
) -> str:
    """プロンプトを構築する（free/premium 共通）。

    target_wordsが指定された場合はそれらの単語を含む例文を生成するよう指示する。
    estimated_vocabに基づいて文章の難易度を自動調整する。
    free ティアではテーマ・スタイルの選択肢が制限される。

    Args:
        params: クライアントから渡されたパラメータ辞書
        target_words: UVMから選定されたターゲット単語リスト（省略可）
        estimated_vocab: ユーザーの語彙スコア（デフォルト0=入門）
        is_premium: プレミアムティアかどうか（free時はテーマ・スタイルが制限される）

    Returns:
        str: OpenAI に送信するプロンプト文字列
    """
    diff = get_difficulty(estimated_vocab)

    resolved = resolve_generation_params(
        params,
        is_premium=is_premium,
        target_words=target_words,
        estimated_vocab=estimated_vocab,
    )
    topic = resolved["topic"]
    style = resolved["style"]
    politeness = resolved["politeness"]
    grammar_focus = resolved["grammarFocus"]
    emotion = resolved["emotion"]
    grammar_line = f"- 文法フォーカス: {grammar_focus}\n" if grammar_focus else ""

    if target_words:
        words_str = ", ".join(target_words)
        return f"""日本語話者向けのタイ語練習文を1つ生成してください。

【最優先】以下のタイ語単語を必ず含めてください:
{words_str}

【必須】難易度:
- 語彙レベル: {diff["label"]}（{diff["vocab_hint"]}）
- 長さ: {diff["length"]}

【可能な限り反映】以下の要素を、自然なタイ語になる範囲で取り入れてください。
- テーマ: {topic}
- 文体: {style}
- 丁寧さ: {politeness}
{grammar_line}- 感情・トーン: {emotion}

- thai_textはタイ語の自然な本文表記にし、単語ごとの分かち書きスペースを入れないでください（OK: ฉันกินข้าว / NG: ฉัน กิน ข้าว）
- 単語単位の区切りはword_breakdownで表現し、thai_text内では文末・節区切りなどタイ語として自然な空白だけを使ってください
- 単語分解は最大20単語まで
- 同じ単語が文中に複数回出現する場合は、出現順にすべてword_breakdownに含めてください
- contextの各フィールドは簡潔に（各50文字以内）
- word_breakdownのmeaningは必ず日本語で記述してください（英語不可）"""

    return f"""日本語話者向けのタイ語練習文を1つ生成してください。

要件:
- 語彙レベル: {diff["label"]}（{diff["vocab_hint"]}）
- 長さ: {diff["length"]}
- テーマ: {topic}
- 文体: {style}
- 丁寧さ: {politeness}
{grammar_line}- 感情・トーン: {emotion}
- thai_textはタイ語の自然な本文表記にし、単語ごとの分かち書きスペースを入れないでください（OK: ฉันกินข้าว / NG: ฉัน กิน ข้าว）
- 単語単位の区切りはword_breakdownで表現し、thai_text内では文末・節区切りなどタイ語として自然な空白だけを使ってください
- 単語分解は最大20単語まで
- 同じ単語が文中に複数回出現する場合は、出現順にすべてword_breakdownに含めてください
- contextの各フィールドは簡潔に（各50文字以内）
- word_breakdownのmeaningは必ず日本語で記述してください（英語不可）"""
