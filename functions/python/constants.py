"""
「まいにちタイ語」アプリ — 定数定義モジュール

このファイルでは、タイ語例文生成に使用する各種定数を定義しています。

定義内容:
  - LLM プロバイダー切替 / モデル名 / APIパラメータ
  - 例文生成に使用する選択肢リスト（テーマ、文体、丁寧さ、文法、感情等）
  - 無料/有料ティアごとの選択肢サブセット
  - レスポンスの JSON Schema 定義（OpenAI/Gemini 共通で使用）

例文生成時、これらのリストからランダムに選択するか、
ユーザーが指定したパラメータを使用してプロンプトを構築します。
"""

import copy
import os

# ─── LLM プロバイダー切替 ───
# "openai" または "gemini"。環境変数 SENTENCE_PROVIDER で上書き可。
SENTENCE_PROVIDER = os.environ.get("SENTENCE_PROVIDER", "gemini").lower()

# ─── OpenAI モデル設定 ───
OPENAI_MODEL = "gpt-5.4-mini"
OPENAI_MODEL_PREMIUM = "gpt-5.4-mini"

# ─── Gemini モデル設定 ───
# 環境変数で上書き可。dev でのモデル検証時に再デプロイのみで切替できるようにしている。
# gemini-2.5 系は 2026-08 時点で新規APIキーからは利用不可（404: no longer available
# to new users）。キーをローテートすると即座に生成が全停止するため 3.x 系を使う。
GEMINI_MODEL = os.environ.get("GEMINI_MODEL", "gemini-3.1-flash-lite")
GEMINI_MODEL_PREMIUM = os.environ.get("GEMINI_MODEL_PREMIUM", "gemini-3.1-flash-lite")

# ─── API パラメータ ───
# 最大出力トークン数: JSON形式のレスポンス（例文＋単語分解＋コンテキスト）に十分な量
API_MAX_TOKENS = 8192

# ─── ティア制限 ───
# 無料ティアの語彙上限（頻度順位）
FREE_TIER_MAX_VOCAB = 100

# ─── 新規ユーザー初期クォータ ───
# users/{uid} doc が未作成のまま生成された場合の初期値。
# 主経路は onUserCreate トリガー（functions/javascript/src/constants/quota.ts）。
# doc 欠損時のフォールバックとしてここでも初期化するため、必ず quota.ts と値を一致させること。
FREE_DAILY_SENTENCES = 5
FREE_DAILY_QUIZZES = 5
PREMIUM_TRIAL_SENTENCES = 5

# ─── 文体リスト ───
# 生成する例文の文体バリエーション。タイ語には場面に応じた多様な文体がある
STYLES = [
    "ニュース記事体（客観的・フォーマルな報道文体）",
    "口語体（友達同士のカジュアルな話し言葉）",
    "丁寧語（フォーマルな敬語・丁寧な表現）",
    "SNS・テキストメッセージ（略語・絵文字・短い表現）",
    "物語・文学体（描写的・書き言葉的な表現）",
]

# ─── テーマリスト ───
# 例文のテーマ。日常会話からタイ文化まで幅広いシーンをカバー
TOPICS = [
    "あいさつ（朝・昼・夜、初対面、再会、別れ、電話）",
    "食べ物（注文、感想、屋台、辛さ調整、アレルギー）",
    "旅行（ホテル、道案内、観光地、空港、ツアー）",
    "仕事（報告・連絡・相談、打ち合わせ、残業申請、同僚雑談）",
    "家族（家族紹介、子育て、親への感謝、兄弟、家族行事）",
    "買い物（値段交渉、サイズ・色の確認、返品、ナイトマーケット）",
    "交通（Grab、BTS、バイタク、ソンテウ、渋滞）",
    "健康（症状説明、薬局、マッサージ、健康診断）",
    "天気（暑さ、雨季、台風、日焼け対策）",
    "趣味（ムエタイ、音楽、映画、ゴルフ、SNS、ゲーム）",
    "学校（授業中、宿題、試験、放課後、語学学校）",
    "宗教・信仰（寺院マナー、托鉢、お守り、僧侶への話し方、仏教行事）",
    "伝統・祭り（ソンクラーン、ロイクラトン、王室行事、地域の伝統料理）",
    "礼儀作法（ワイの使い分け、敬語、タブー、食事マナー、贈り物）",
    "恋愛・男女関係（告白、デート、甘い言葉、遠距離、別れ、仲直り）",
    "タイBLドラマ（告白、すれ違い、再会、嫉妬、裏切り、仲直り、壁ドン、あだ名呼び）",
]

# ─── サブテーマ辞書 ───
# テーマごとのサブテーマ。単語embeddingとの類似度で重みつきランダム選出される。
TOPIC_SUB_THEMES: dict[str, list[str]] = {
    TOPICS[0]: ["朝", "昼", "夜", "初対面", "再会", "別れ", "電話"],
    TOPICS[1]: ["注文", "感想", "屋台", "辛さ調整", "アレルギー"],
    TOPICS[2]: ["ホテル", "道案内", "観光地", "空港", "ツアー"],
    TOPICS[3]: ["報告・連絡・相談", "打ち合わせ", "残業申請", "同僚雑談"],
    TOPICS[4]: ["家族紹介", "子育て", "親への感謝", "兄弟", "家族行事"],
    TOPICS[5]: ["値段交渉", "サイズ・色の確認", "返品", "ナイトマーケット"],
    TOPICS[6]: ["Grab", "BTS", "バイタク", "ソンテウ", "渋滞"],
    TOPICS[7]: ["症状説明", "薬局", "マッサージ", "健康診断"],
    TOPICS[8]: ["暑さ", "雨季", "台風", "日焼け対策"],
    TOPICS[9]: ["ムエタイ", "音楽", "映画", "ゴルフ", "SNS", "ゲーム"],
    TOPICS[10]: ["授業中", "宿題", "試験", "放課後", "語学学校"],
    TOPICS[11]: ["寺院マナー", "托鉢", "お守り", "僧侶への話し方", "仏教行事"],
    TOPICS[12]: ["ソンクラーン", "ロイクラトン", "王室行事", "地域の伝統料理"],
    TOPICS[13]: ["ワイの使い分け", "敬語", "タブー", "食事マナー", "贈り物"],
    TOPICS[14]: ["告白", "デート", "甘い言葉", "遠距離", "別れ", "仲直り"],
    TOPICS[15]: ["告白", "すれ違い", "再会", "嫉妬", "裏切り", "仲直り", "壁ドン", "あだ名呼び", "同棲", "片想い"],
}


# ─── 無料ティア用サブセット ───
# 無料ユーザーは基本的なテーマと文体のみ利用可能
FREE_TOPICS = [
    TOPICS[0],
    TOPICS[1],
    TOPICS[5],
    TOPICS[15],
]  # あいさつ、食べ物、買い物、タイBLドラマ
FREE_STYLES = STYLES[1:3]  # 口語体、丁寧語

# ─── 丁寧さレベル ───
# タイ語は丁寧さの使い分けが重要。場面に応じたレベルを選択
POLITENESS_LEVELS = [
    "フォーマル（丁寧語・敬語を使用）",
    "カジュアル（くだけた友達同士の表現）",
    "中立（一般的な日常表現）",
]

# ─── 文法フォーカス ───
# 特定の文法パターンを含む例文を生成するための選択肢（有料ティア限定）
GRAMMAR_FOCUSES = [
    "平叙文（基本の肯定文）",
    "疑問文（〜ไหม？〜มั้ย？など）",
    "否定文（ไม่〜、ไม่ได้〜など）",
    "条件文（ถ้า〜、หาก〜など）",
    "比較表現（กว่า、เหมือนなど）",
    "命令・依頼（〜นะ、〜ด้วยなど）",
    "可能表現（ได้、เป็นなど）",
    "過去・完了（แล้ว、เคยなど）",
    "助詞・接続詞（แต่、และ、หรือなど）",
]


# ─── 感情・トーン ───
# 例文に含める感情表現の種類
EMOTIONS = [
    "喜び・嬉しさ",
    "悲しみ・落ち込み",
    "驚き",
    "不安・心配",
    "期待・楽しみ",
    "中立・平静",
]


# ─── OpenAI Responses API レスポンススキーマ ───
# OpenAI の structured outputs が準拠すべき JSON Schema を定義する。
# これにより、構造化されたタイ語例文データが確実に返却される。
# context.topic / style / emotion はサーバー側で確定済みのためスキーマから除外し、
# 生成後に prompts.resolve_generation_params() の結果を注入する（出力トークン削減）。
RESPONSE_JSON_SCHEMA = {
    "type": "object",
    "additionalProperties": False,
    "properties": {
        "thai_text": {
            "type": "string",
            "description": "タイ語の例文テキスト（例: สวัสดีครับ）",
        },
        "japanese_translation": {
            "type": "string",
            "description": (
                "自然な日本語訳。主語・話者の違いが意味に関わる場合だけ訳に残す。"
                "強調・語調・反語表現は逐語訳せず話し言葉の等価表現にする"
            ),
        },
        "word_breakdown": {
            "type": "array",
            "description": "例文を構成する各単語と日本語の意味。最大20件。",
            "items": {
                "type": "object",
                "additionalProperties": False,
                "properties": {
                    "word": {
                        "type": "string",
                        "description": "タイ語の単語（例: สวัสดี）",
                    },
                    "meaning": {
                        "type": "string",
                        "description": "単語の意味を必ず日本語で記述すること（英語不可）",
                    },
                },
                "required": ["word", "meaning"],
            },
        },
        "target_notes": {
            "type": "array",
            "description": "ターゲット単語のみの補足。ターゲット単語が無ければ空配列。",
            "items": {
                "type": "object",
                "additionalProperties": False,
                "properties": {
                    "word": {
                        "type": "string",
                        "description": "対象のタイ語単語（word_breakdown の word と一致させる）",
                    },
                    "note": {
                        "type": "string",
                        "description": "用法・ニュアンス・類語との違い（日本語、50文字以内）",
                    },
                },
                "required": ["word", "note"],
            },
        },
        "context": {
            "type": "object",
            "additionalProperties": False,
            "properties": {
                "usage_scenarios": {
                    "type": "string",
                    "description": "使用場面の説明。50文字以内。",
                },
                "cultural_notes": {
                    "type": "string",
                    "description": "文化的な補足情報。50文字以内。",
                },
            },
            "required": [
                "usage_scenarios",
                "cultural_notes",
            ],
        },
    },
    "required": [
        "thai_text",
        "japanese_translation",
        "word_breakdown",
        "target_notes",
        "context",
    ],
}

# ─── context のうち LLM に生成させうるフィールド ───
# 通常はサーバーがプロンプトで指定するため確定値を注入すればよく、
# LLM に復唱させない（出力トークン削減）。
# ただし指定せずに生成させる場合（例: BLドラマ回は文体・トーンを制約しない）は
# 確定値が存在しないので、そのフィールドだけスキーマに戻して LLM に書かせる。
_CONTEXT_GENERATABLE_FIELDS = {
    "topic": {"type": "string", "description": "テーマ（例: あいさつ）"},
    "style": {"type": "string", "description": "文体（例: 丁寧語）"},
    "emotion": {"type": "string", "description": "感情・トーン（例: 中立）"},
}


def build_response_schema(ask_context_fields: tuple[str, ...] = ()) -> dict:
    """リクエストごとのレスポンススキーマを組み立てる。

    Args:
        ask_context_fields: LLM に生成させる context フィールド名。
            プロンプトで値を指定しなかったものだけを渡すこと。

    Returns:
        dict: RESPONSE_JSON_SCHEMA のコピー。指定フィールドを context に追加済み。
    """
    if not ask_context_fields:
        return RESPONSE_JSON_SCHEMA

    schema = copy.deepcopy(RESPONSE_JSON_SCHEMA)
    context = schema["properties"]["context"]
    for name in ask_context_fields:
        field = _CONTEXT_GENERATABLE_FIELDS.get(name)
        if field is None:
            continue
        context["properties"][name] = dict(field)
        context["required"].append(name)
    return schema
