"""
「まいにちタイ語」アプリ — プロンプト構築モジュール

OpenAI に送信するプロンプト（指示文）を構築する。
free / premium ともに build_uvm_prompt を使用する。
estimated_vocab が 100 以下の間は free / premium 共通の入門プロンプトを使う。
free ティアは estimated_vocab が 100 以下にキャップされる。
"""

import random

from constants import (
    EMOTIONS,
    FREE_STYLES,
    FREE_TOPICS,
    GRAMMAR_FOCUSES,
    POLITENESS_LEVELS,
    STYLES,
    TOPICS,
    TOPIC_SUB_THEMES,
)
from embeddings import (
    find_best_sub_theme,
    get_emotion_similarity_weights,
    get_style_similarity_weights,
    get_topic_option_similarity_weights,
)
from themes.bl_drama import build_drama_prompt_section


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
    TOPICS[15]: 100,  # タイドラマ
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


# ─── システムプロンプト（固定・プロバイダー共通） ───
# プロンプトキャッシュを効かせるため、呼び出しごとに変化しない指示は
# ここに集約して prefix として送る（OpenAI=instructions / Gemini=system_instruction）。
SYSTEM_PROMPT_FREE = """タイ語基礎練習文を1つ生成。以下を厳守。

方針: 短く実用的な入門〜初級文。基本語順・基本動詞・日常名詞中心。複文・慣用表現・強い感情表現は避ける。分かりやすさ優先。contextは一般的な説明に留める。

出力ルール:
- thai_text: 分かち書き禁止（OK: ฉันกินข้าว / NG: ฉัน กิน ข้าว）。自然な空白のみ
- word_breakdown: 最大20単語、出現順にすべて含める。meaningは日本語のみ
- 人称代名詞のmeaningに性別・丁寧度注記（例: ผม→「私（男性・丁寧）」、กู→「俺/私（男女・ぞんざい）」）
- context各フィールド50文字以内
- japanese_translation: 自然な日本語。主語・目的語の対応を崩さない（誰が・誰を・何をの関係を正確に）（×説明的な訳→○日本語として自然な形）
- 強調・限定・語調の表現は逐語訳せず、日本語の話し言葉としての等価表現に置き換える（例: สำหรับฉัน→×「私については」○「私のこともね」）
- target_notesにはターゲット単語だけを入れ、用法・類語との違いを50文字以内で記述
- スペルミス厳禁: เธอをเธと書かない。母音-อを落とさない
- ターゲット単語は独立した意味で使用（慣用句・複合語の一部のみはNG。畳語は除く）
- ターゲット単語はword_breakdownに独立エントリとして含める
- 性的表現・露骨な恋愛描写は禁止。恋愛テーマでも健全な範囲に留める"""


SYSTEM_PROMPT_PREMIUM = """タイ語練習文を1つ生成。

# 出力フォーマット
- thai_text: 語ごとの分かち書きは禁止（NG: ฉัน กิน ข้าว）。節・句など意味のまとまりの区切りとしての空白は可（OK: ฉันกินข้าว / ...ทำ แต่...）
- word_breakdown: 最大20単語、出現順に全て。meaningは日本語のみ。人称代名詞は性別・丁寧度を注記（例: ผม→「私（男性・丁寧）」）
- context: 各フィールド50文字以内
- japanese_translation: 自然で簡潔な日本語。時制はタイ語と一致。主語・目的語の対応を正確に（誰が誰を何を）。説明的な直訳は避ける
- 強調・限定・語調・反語は逐語訳せず話し言葉の等価表現に。硬い直訳（「〜については」「何のために」等）禁止。例: สำหรับฉัน คิดถึงฉันบ้างนะ →「私のこともね、たまには思い出してね」／〜เพื่ออะไร（反語）→「〜しなくていいよ」
- target_notes: ターゲット単語のみ。用法・類語との違いを50文字以内

# 構文ルール（最重要）
- 動詞中心の自然なタイ語。直訳構文禁止
- 主題優勢言語。既知の話題（物・事）は文頭に主題として置く（×เราจะใช้รายงานนี้พรุ่งนี้ได้ไหม →○รายงานนี้พรุ่งนี้ใช้ได้ไหม）。英語的SVOを避ける
- 人称の一貫性。短い会話で一・二・三人称（ผม/กู・คุณ/มึง・เขา等）を無根拠に混ぜない。指示対象が未確立の第三者（เขา等）を主語にしない（×มึงจะให้กูทำ แต่เขาไม่สนใจ →○...แต่กูไม่สนใจ）
- คุณคือ〜多用禁止→感情はทำให้〜、説明はเป็นคนที่〜
- ความ〜の硬い主語・補語は避ける（フォーマル・上級は可）。抽象名詞でなく具体的現象を主語に
- 場所→ที่นี่、状況→แบบนี้（カジュアル: งี้）
- 過去は〜แล้ว/ตอน〜優先。冗長なเมื่อ〜ก็〜は避ける
- 会話はนะ/ดูで柔らかく。複文はเพราะ/เพื่อ/แล้วで接続
- ได้+動詞は経験・機会として使用
- 英語由来語は語尾・補足で自然に（โอเคแล้วนะ等）
- 指示・依頼はช่วย〜หน่อย/รบกวน〜หน่อย優先
- ターゲット単語は独立した意味で使用（複合語の一部のみNG。畳語は除く）。word_breakdownに独立エントリで含める
- ターゲット動詞は自然に共起する具体的な目的語と組ませる。汎用の埋め草（เรื่อง/สิ่ง/อะไร等）で不自然に埋めない（×ปกป้องเรื่องนั้น →○ปกป้องคุณ/ปกป้องความลับ）
- 性的・露骨な恋愛描写は禁止。恋愛テーマも健全な範囲に

出力前確認: 自然か？直訳でないか？スペルミスは？"""


# 後方互換: 既存 import は premium 用プロンプトを参照する。
SYSTEM_PROMPT = SYSTEM_PROMPT_PREMIUM


def use_premium_prompt_for_vocab(is_premium: bool, estimated_vocab: int) -> bool:
    """Premium ユーザーは常に Premium プロンプトを使う。"""
    return is_premium


def get_system_prompt(
    is_premium: bool,
    estimated_vocab: int | None = None,
) -> str:
    """tier と語彙スコアに応じた固定システムプロンプトを返す。"""
    if estimated_vocab is not None:
        is_premium = use_premium_prompt_for_vocab(is_premium, estimated_vocab)
    return SYSTEM_PROMPT_PREMIUM if is_premium else SYSTEM_PROMPT_FREE


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


def _style_weights(
    target_words: list[str] | None, styles_pool: list[str]
) -> list[float]:
    global _style_embedding_enabled
    if not _style_embedding_enabled:
        return [1.0] * len(styles_pool)

    try:
        weights = get_style_similarity_weights(target_words, styles_pool)
    except Exception as exc:
        _style_embedding_enabled = False
        print(f"style embedding weights unavailable: {exc}")
        weights = None
    return weights or [1.0] * len(styles_pool)


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
    if is_premium:
        topics_pool = _gate_topics(topics_pool, estimated_vocab)
    styles_pool = _gate_pool(styles_pool, estimated_vocab, STYLE_MIN_VOCAB)

    topic = params.get("topic") or random.choice(topics_pool)
    style = params.get("style")
    if not style:
        style = _weighted_choice(
            styles_pool,
            _style_weights(target_words, styles_pool),
        )

    politeness = params.get("politeness")
    if not politeness:
        if topic == TOPICS[15]:
            politeness = POLITENESS_LEVELS[1]
        else:
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

    sub_theme = None
    sub_themes = TOPIC_SUB_THEMES.get(topic)
    if sub_themes and target_words:
        sub_theme = find_best_sub_theme(target_words[0], sub_themes)

    return {
        "topic": topic,
        "subTheme": sub_theme,
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
    """プロンプト文字列のみを返す薄いラッパー。"""
    return build_prompt_with_context(
        params,
        target_words,
        estimated_vocab=estimated_vocab,
        is_premium=is_premium,
    )[0]


def build_prompt_with_context(
    params: dict,
    target_words: list[str] | None = None,
    estimated_vocab: int = 0,
    is_premium: bool = True,
) -> tuple[str, dict]:
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
        tuple[str, dict]: プロンプト文字列と、生成後に context へ注入する
            {"topic", "style", "emotion"}（LLM に復唱させず出力トークンを節約する）
    """
    diff = get_difficulty(estimated_vocab)
    prompt_is_premium = use_premium_prompt_for_vocab(is_premium, estimated_vocab)

    resolved = resolve_generation_params(
        params,
        is_premium=prompt_is_premium,
        target_words=target_words,
        estimated_vocab=estimated_vocab,
    )
    topic = resolved["topic"]
    sub_theme = resolved["subTheme"]
    style = resolved["style"]
    politeness = resolved["politeness"]
    grammar_focus = resolved["grammarFocus"]
    emotion = resolved["emotion"]
    grammar_line = f"- 文法フォーカス: {grammar_focus}\n" if grammar_focus else ""
    sub_theme_line = f"- サブテーマ: {sub_theme}\n" if sub_theme else ""

    drama_context = ""
    drama_required = ""
    is_drama = topic == TOPICS[15]
    if is_drama:
        drama = build_drama_prompt_section(target_words)
        drama_context = drama["context"]
        drama_required = drama["required"]
    if is_drama:
        topic_line = ""
        sub_theme_line = ""
        style_line = ""
        politeness_line = ""
        grammar_line = ""
        emotion_line = ""
    else:
        topic_line = f"- テーマ: {topic}\n"
        style_line = f"- 文体: {style}\n"
        politeness_line = f"- 丁寧さ: {politeness}\n"
        emotion_line = f"- 感情・トーン: {emotion}"
        # grammar_line is already set above

    # プロンプトで指定した値のみ確定値として記録する。
    # ドラマ回は文体・トーンを制約しないため確定値が無く、キーごと落とす。
    # 欠けたキーは呼び出し側が LLM に生成させる（constants.build_response_schema）。
    context = {"topic": topic}
    if not is_drama:
        context["style"] = style
        context["emotion"] = emotion

    if target_words:
        words_str = ", ".join(target_words)
        return f"""【最優先】以下のタイ語単語を必ず含めてください:
{words_str}
- 各ターゲット単語はそれ自体で独立した意味を持つ形で使用してください。慣用句・複合語・熟語の一部としてのみ登場させることは禁止です（例: ข้า を ข้าพเจ้า の一部としてだけ使うのはNG。ข้า 単独で意味が成り立つ文にしてください）
- 例外: 畳語・繰り返し表現（เด็กๆ, ช้าๆ 等）は許可します
- word_breakdownには各ターゲット単語を独立したエントリとして必ず含めてください。複合語にまとめず、単語単位で分解してください

{drama_context}
【必須】難易度:
- 語彙レベル: {diff["label"]}（{diff["vocab_hint"]}）
- 長さ: {diff["length"]}
{drama_required}
【キーワード補足】上記のターゲット単語には、target_notesで用法・ニュアンス・類語との違いを簡潔に補足してください。


【可能な限り反映】以下の要素を、自然なタイ語になる範囲で取り入れてください。
{topic_line}{sub_theme_line}{style_line}{politeness_line}{grammar_line}{emotion_line}""", context

    return f"""
{drama_context}
【必須】難易度:
- 語彙レベル: {diff["label"]}（{diff["vocab_hint"]}）
- 長さ: {diff["length"]}
{drama_required}
【可能な限り反映】以下の要素を、自然なタイ語になる範囲で取り入れてください。
{topic_line}{sub_theme_line}{style_line}{politeness_line}{grammar_line}{emotion_line}""", context
