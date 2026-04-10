"""
「まいにちタイ語」アプリ — 定数定義モジュール

このファイルでは、タイ語例文生成に使用する各種定数を定義しています。

定義内容:
  - Gemini AI モデル名とAPIパラメータ（温度、最大トークン数）
  - 例文生成に使用する選択肢リスト（トピック、文体、丁寧さ、文法、感情等）
  - 無料/有料ティアごとの選択肢サブセット
  - Gemini API レスポンスの JSON スキーマ定義

例文生成時、これらのリストからランダムに選択するか、
ユーザーが指定したパラメータを使用してプロンプトを構築します。
"""

from google.genai import types

# ─── Gemini AI モデル設定 ───
# 無料ティア用: 軽量・高速な lite モデル
GEMINI_MODEL = "gemini-2.5-flash"
# 有料ティア用: 高品質な標準モデル
GEMINI_MODEL_PREMIUM = "gemini-2.5-flash"

# ─── API パラメータ ───
# 温度（0.0〜1.0）: 高いほど多様な出力が得られる。0.8は創造的な例文生成に適した値
API_TEMPERATURE = 0.8
# 最大出力トークン数: JSON形式のレスポンス（例文＋単語分解＋コンテキスト）に十分な量
API_MAX_TOKENS = 8192

# ─── ティア制限 ───
# 無料ティアの語彙上限（頻度順位）
FREE_TIER_MAX_VOCAB = 300

# ─── 文体リスト ───
# 生成する例文の文体バリエーション。タイ語には場面に応じた多様な文体がある
STYLES = [
    "ニュース記事体（客観的・フォーマルな報道文体）",
    "口語体（友達同士のカジュアルな話し言葉）",
    "丁寧語（フォーマルな敬語・丁寧な表現）",
    "SNS・テキストメッセージ（略語・絵文字・短い表現）",
    "物語・文学体（描写的・書き言葉的な表現）",
]

# ─── トピックリスト ───
# 例文のテーマ。日常会話からタイ文化まで幅広いシーンをカバー
TOPICS = [
    "あいさつ（朝・昼・夜、初対面、再会、別れ、電話）",
    "食べ物（注文、感想、屋台、辛さ調整、アレルギー）",
    "旅行（ホテル、道案内、観光地、空港、ツアー）",
    "感情（喜び、悲しみ、驚き、不安、怒り、照れ）",
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
]

# ─── 無料ティア用サブセット ───
# 無料ユーザーは基本的なトピックと文体のみ利用可能
# 無料ティア用サブセット
FREE_TOPICS = [
    TOPICS[0],
    TOPICS[1],
    TOPICS[2],
    TOPICS[6],
]  # あいさつ、食べ物、旅行、買い物
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
    "感謝",
    "期待・楽しみ",
    "中立・平静",
]


# ─── Gemini API レスポンススキーマ ───
# Gemini API のレスポンスが準拠すべき JSON スキーマを定義する。
# これにより、構造化されたタイ語例文データが確実に返却される。
RESPONSE_SCHEMA = types.Schema(
    type=types.Type.OBJECT,
    properties={
        # タイ語の例文テキスト（例: "สวัสดีครับ"）
        "thai_text": types.Schema(type=types.Type.STRING),
        # 日本語訳（例: "こんにちは"）
        "japanese_translation": types.Schema(type=types.Type.STRING),
        # 単語分解: 例文を構成する各単語とその意味のリスト
        "word_breakdown": types.Schema(
            type=types.Type.ARRAY,
            items=types.Schema(
                type=types.Type.OBJECT,
                properties={
                    # タイ語の単語（例: "สวัสดี"）
                    "word": types.Schema(type=types.Type.STRING),
                    # 単語の日本語の意味（例: "こんにちは、さようなら"）
                    "meaning": types.Schema(
                        type=types.Type.STRING,
                        description="単語の意味を必ず日本語で記述すること（英語不可）",
                    ),
                },
                required=["word", "meaning"],
            ),
        ),
        # コンテキスト情報: 例文の使用場面や文化的背景
        "context": types.Schema(
            type=types.Type.OBJECT,
            properties={
                # トピック（例: "あいさつ"）
                "topic": types.Schema(type=types.Type.STRING),
                # 文体（例: "丁寧語"）
                "style": types.Schema(type=types.Type.STRING),
                # 感情（例: "中立"）
                "emotion": types.Schema(type=types.Type.STRING),
                # 使用場面の説明（例: "初対面の挨拶で使用"）
                "usage_scenarios": types.Schema(type=types.Type.STRING),
                # 文化的な補足情報（例: "タイでは年長者にはครับ/ค่ะをつける"）
                "cultural_notes": types.Schema(type=types.Type.STRING),
            },
            required=["topic", "style", "emotion", "usage_scenarios", "cultural_notes"],
        ),
    },
    required=["thai_text", "japanese_translation", "word_breakdown", "context"],
)
