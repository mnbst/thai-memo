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
# 2026-08-05 に openai(gpt-5.6-luna) へ全面切替したが、同日 gemini へ差し戻した。
# OpenAI 側のコードは残してあるので SENTENCE_PROVIDER=openai で試せる。
SENTENCE_PROVIDER = os.environ.get("SENTENCE_PROVIDER", "gemini").lower()

# ─── OpenAI モデル設定 ───
# 環境変数で上書き可。モデル検証時に再デプロイのみで切替できるようにしている。
OPENAI_MODEL = os.environ.get("OPENAI_MODEL", "gpt-5.6-luna")
OPENAI_MODEL_PREMIUM = os.environ.get("OPENAI_MODEL_PREMIUM", "gpt-5.6-luna")

# ─── Gemini モデル設定 ───
# 環境変数で上書き可。dev でのモデル検証時に再デプロイのみで切替できるようにしている。
# gemini-2.5 系は 2026-08 時点で新規APIキーからは利用不可（404: no longer available
# to new users）。キーをローテートすると即座に生成が全停止するため 3.x 系を使う。
GEMINI_MODEL = os.environ.get("GEMINI_MODEL", "gemini-3.1-flash-lite")
GEMINI_MODEL_PREMIUM = os.environ.get("GEMINI_MODEL_PREMIUM", "gemini-3.1-flash-lite")

# ─── API パラメータ ───
# 最大出力トークン数: JSON形式のレスポンス（例文＋単語分解＋コンテキスト）に十分な量
API_MAX_TOKENS = 8192

# ─── 対応言語 ───
# 訳文・解説の言語。クライアントが lang を送ってくる。
SUPPORTED_LANGS = ("ja", "en")
DEFAULT_LANG = "ja"


def normalize_lang(value: object) -> str:
    """言語コードを対応言語に正規化する。未知・未設定は ja に倒す。

    日本語ユーザーに英訳が返る事故のほうが、既定言語のまま返すより害が大きい。
    """
    lang = str(value or "").strip().lower()
    return lang if lang in SUPPORTED_LANGS else DEFAULT_LANG


def resolve_lang(data: dict | None) -> str:
    """リクエストの lang を対応言語に正規化する。

    lang を送らない旧クライアントは ja になる（後方互換）。
    サーバー起点の配信には lang を載せたリクエストが無いので、
    そちらは users/{uid}.app_language を normalize_lang に通す。
    """
    return normalize_lang((data or {}).get("lang"))


# ─── ティア制限 ───
# 無料ティアの語彙上限（頻度順位）
FREE_TIER_MAX_VOCAB = 100

# ─── 新規ユーザー初期クォータ ───
# users/{uid} doc が未作成のまま生成された場合の初期値。
# 主経路は onUserCreate トリガー（functions/javascript/src/constants/quota.ts）。
# doc 欠損時のフォールバックとしてここでも初期化するため、必ず quota.ts と値を一致させること。
FREE_DAILY_SENTENCES = 5
FREE_DAILY_QUIZZES = 5

# premium の日次上限。例文は 2026-08-09 に 5 → 10 へ引き上げ（実測で課金者2人が
# 常時上限に当たっていたため）。クイズは到達者が居ないため 5 のまま。
PREMIUM_DAILY_SENTENCES = 10
PREMIUM_DAILY_QUIZZES = 5

# プレミアム体験トライアルは期間制（premium_trial_expires_at）。
# 期間中は機能・回数とも課金 premium と完全に同じ扱いにする。
PREMIUM_TRIAL_DAYS = 2

# premium_trial_remaining の付与値（凍結した互換値）。サーバは読まないし減らさない。
# 〜1.3.14（現行ストア版）のクライアントは「残回数 <= 1 なら体験最終回」としてテーマを解除するため、
# 書かないと体験中の1回目で設定テーマが消える。quota.ts と同じ扱い。
PREMIUM_TRIAL_SENTENCES = PREMIUM_DAILY_SENTENCES * PREMIUM_TRIAL_DAYS

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
# 2026-08-14 削除: FREE_TOPICS（あいさつ・食べ物・買い物・BLドラマの4件）。
# クライアントはテーマを送らず、free/premium ともサーバーが自動選出する。
# free だけプールを狭めても「選べる候補の差」にはならず、テーマの偏りを
# 強めるだけだった（4件では BLドラマが 82.7%）。以降 free も premium と同じ
# TOPICS を TOPIC_MIN_VOCAB でゲートしたプールから選ぶ。選び方だけが違う
# （free=一様抽選 / premium=embedding で key_word に最も近いテーマ）。
# 2026-08-06 削除: FREE_STYLES。文体の自動抽選を止めた時点で参照が消えた
# （prompts.py:build_register_constraint のコメント参照）。

# free の自動選出で BLドラマを出す確率。
# BL は語彙ゲート（TOPIC_MIN_VOCAB=100）の対象で、free は estimated_vocab が
# 100 でキャップされるため、放っておくと入門帯には一切出ない。刺さる層には
# 強い引きなので、レベルに関係なく一定確率で混ぜる。残りは通常の一様抽選
# （BL を除いたゲート済みプール）。バンク生成（scripts/build_free_sentence_bank.py）
# も同じ率で BL 枠を確保する。
FREE_BL_TOPIC_RATE = 0.1
BL_TOPIC = TOPICS[15]

# ─── ヒアリング（オンボーディングの4問）の goal → テーマ候補 ───
# users/{uid}.interview.goal に入る値をテーマ候補に対応づける。候補が複数ある
# ものは生成のたびに一様抽選する（1テーマに固定すると入門帯の旅行偏りを
# 別のテーマに置き換えるだけになる）。
#
# ここで選んだテーマは明示指定として扱われ TOPIC_MIN_VOCAB のゲートを通らない。
# 本人が申告した用途なので入門帯でも出してよいという判断。
#
# 候補はヒアリング最終画面の文言（l10n philosophy3Travel/Work/Live/Culture）が
# 名指ししているテーマを必ず含める。「『旅行』や『交通』が届きます」と伝えた
# 相手に別のテーマを出すと、その場で反故になる。伝統・祭り（600ゲート）を
# culture に入れているのはこのため。学校・宗教・礼儀作法はどの文言でも
# 触れていないので、語彙要求の高さを取って候補に入れない。
INTERVIEW_GOAL_TOPICS: dict[str, list[str]] = {
    # philosophy3Travel: 旅行・交通
    "travel": [TOPICS[2], TOPICS[6], TOPICS[5], TOPICS[1]],  # +買い物/食べ物
    # philosophy3Work: 仕事
    "work": [TOPICS[3], TOPICS[0]],  # +あいさつ（職場の挨拶）
    # philosophy3Live: 買い物・家族
    "live": [TOPICS[5], TOPICS[4], TOPICS[7], TOPICS[8], TOPICS[6], TOPICS[1]],
    # philosophy3Culture: タイBLドラマ・伝統・祭り
    "culture": [TOPICS[15], TOPICS[12], TOPICS[9], TOPICS[14]],  # +趣味/恋愛
}

# ─── 丁寧さレベル ───
# タイ語は丁寧さの使い分けが重要。場面に応じたレベルを選択
# 2026-08-07 削除: POLITENESS_LEVELS。丁寧さをプロンプトに渡すのをやめたため
# 参照元が消えた（120文×3バッチで丁寧体率 42/44/42% と動かず、死にパラメータだった）。

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


# 2026-08-06 削除: EMOTIONS。感情の自動抽選を止めた時点で生成経路から参照が消え、
# 残っていたのは scripts/build_emotion_embeddings.py → corpus/emotion_embeddings.json
# → GCS という経路だけだった。この blob をロードするコードは存在しないため、
# 定数・ビルドスクリプト・upload_corpus.sh の分岐をまとめて削除した。
# 感情は現在 LLM が生成して context.emotion に返す（自由記述）。


# ─── 時間軸 ───
# 2026-08-05 追加。grammarFocus / emotion の自動抽選を止めた結果、
# 組み合わせが topic×subTheme×style×politeness の約400通りまで落ちたため、
# key_word の意味を制約しない直交軸として足す。
# いつのことを話しているか。相（กำลัง/แล้ว/จะ/เคย）の多様性を副次的に回収する。
# どのテーマでもこの4つは全て成立するので、テーマ側の絞り込みが要らない。
TIME_FRAMES = [
    "今まさに起きていること",
    "さっき起きた出来事",
    "これからの予定",
    "いつもの習慣",
]


# ─── 軸ラベルの英語表記 ───
# topic / subTheme / timeFrame はサーバーが日本語の定数から決めて context に記録し、
# style は LLM が STYLES の日本語ラベルをそのまま返す。en ユーザーの画面にその
# 日本語が出るため、保存・返却の直前に localize_context で英語へ差し替える。
# プロンプト側は日本語のまま触らない（調整済みの成果物であり、英訳すると
# 出力の傾向が変わってしまう）。
TIME_FRAME_LABELS_EN: dict[str, str] = {
    TIME_FRAMES[0]: "Happening right now",
    TIME_FRAMES[1]: "Something that just happened",
    TIME_FRAMES[2]: "An upcoming plan",
    TIME_FRAMES[3]: "A regular habit",
}

STYLE_LABELS_EN: dict[str, str] = {
    STYLES[0]: "News article style (objective, formal reporting)",
    STYLES[1]: "Casual spoken style (how friends talk)",
    STYLES[2]: "Polite style (formal, respectful expressions)",
    STYLES[3]: "Social media / text message style (abbreviations, emoji, short phrases)",
    STYLES[4]: "Narrative / literary style (descriptive, written language)",
}

TOPIC_LABELS_EN: dict[str, str] = {
    TOPICS[0]: "Greetings (morning, noon, night, first meeting, reunion, farewell, phone)",
    TOPICS[1]: "Food (ordering, impressions, street stalls, spice level, allergies)",
    TOPICS[2]: "Travel (hotels, directions, sights, airport, tours)",
    TOPICS[3]: "Work (reporting, meetings, overtime requests, chatting with coworkers)",
    TOPICS[4]: "Family (introductions, parenting, thanking parents, siblings, family events)",
    TOPICS[5]: "Shopping (haggling, size and color, returns, night markets)",
    TOPICS[6]: "Getting around (Grab, BTS, motorbike taxi, songthaew, traffic)",
    TOPICS[7]: "Health (describing symptoms, pharmacy, massage, checkups)",
    TOPICS[8]: "Weather (heat, rainy season, storms, sun protection)",
    TOPICS[9]: "Hobbies (Muay Thai, music, movies, golf, social media, games)",
    TOPICS[10]: "School (in class, homework, exams, after school, language school)",
    TOPICS[11]: (
        "Religion and faith (temple etiquette, alms giving, amulets, "
        "speaking to monks, Buddhist holidays)"
    ),
    TOPICS[12]: (
        "Traditions and festivals (Songkran, Loi Krathong, royal ceremonies, "
        "regional dishes)"
    ),
    TOPICS[13]: "Etiquette (the wai, honorifics, taboos, table manners, gifts)",
    TOPICS[14]: (
        "Romance (confessions, dates, sweet talk, long distance, breakups, "
        "making up)"
    ),
    TOPICS[15]: (
        "Thai BL drama (confessions, misunderstandings, reunions, jealousy, "
        "betrayal, making up, kabedon, nicknames)"
    ),
}

# サブテーマはテーマごとに引く。「別れ」があいさつでは farewell、恋愛では
# breakup になるように、同じ日本語でもテーマで訳が変わるため平坦な辞書にしない。
SUB_THEME_LABELS_EN: dict[str, dict[str, str]] = {
    TOPICS[0]: {
        "朝": "morning", "昼": "midday", "夜": "evening",
        "初対面": "meeting for the first time", "再会": "meeting again",
        "別れ": "saying goodbye", "電話": "on the phone",
    },
    TOPICS[1]: {
        "注文": "ordering", "感想": "giving impressions", "屋台": "street stalls",
        "辛さ調整": "adjusting spice level", "アレルギー": "allergies",
    },
    TOPICS[2]: {
        "ホテル": "hotels", "道案内": "directions", "観光地": "sights",
        "空港": "the airport", "ツアー": "tours",
    },
    TOPICS[3]: {
        "報告・連絡・相談": "reporting and consulting", "打ち合わせ": "meetings",
        "残業申請": "requesting overtime", "同僚雑談": "small talk with coworkers",
    },
    TOPICS[4]: {
        "家族紹介": "introducing family", "子育て": "parenting",
        "親への感謝": "thanking parents", "兄弟": "siblings",
        "家族行事": "family events",
    },
    TOPICS[5]: {
        "値段交渉": "haggling", "サイズ・色の確認": "checking size and color",
        "返品": "returns", "ナイトマーケット": "night markets",
    },
    TOPICS[6]: {
        "Grab": "Grab", "BTS": "the BTS", "バイタク": "motorbike taxis",
        "ソンテウ": "songthaew", "渋滞": "traffic jams",
    },
    TOPICS[7]: {
        "症状説明": "describing symptoms", "薬局": "the pharmacy",
        "マッサージ": "massage", "健康診断": "health checkups",
    },
    TOPICS[8]: {
        "暑さ": "the heat", "雨季": "the rainy season", "台風": "storms",
        "日焼け対策": "sun protection",
    },
    TOPICS[9]: {
        "ムエタイ": "Muay Thai", "音楽": "music", "映画": "movies",
        "ゴルフ": "golf", "SNS": "social media", "ゲーム": "games",
    },
    TOPICS[10]: {
        "授業中": "during class", "宿題": "homework", "試験": "exams",
        "放課後": "after school", "語学学校": "language school",
    },
    TOPICS[11]: {
        "寺院マナー": "temple etiquette", "托鉢": "alms giving",
        "お守り": "amulets", "僧侶への話し方": "speaking to monks",
        "仏教行事": "Buddhist holidays",
    },
    TOPICS[12]: {
        "ソンクラーン": "Songkran", "ロイクラトン": "Loi Krathong",
        "王室行事": "royal ceremonies", "地域の伝統料理": "regional dishes",
    },
    TOPICS[13]: {
        "ワイの使い分け": "when to wai", "敬語": "honorifics", "タブー": "taboos",
        "食事マナー": "table manners", "贈り物": "gifts",
    },
    TOPICS[14]: {
        "告白": "confessing feelings", "デート": "dates",
        "甘い言葉": "sweet talk", "遠距離": "long distance",
        "別れ": "breaking up", "仲直り": "making up",
    },
    TOPICS[15]: {
        "告白": "confessing feelings", "すれ違い": "misunderstandings",
        "再会": "reuniting", "嫉妬": "jealousy", "裏切り": "betrayal",
        "仲直り": "making up", "壁ドン": "kabedon", "あだ名呼び": "nicknames",
        "同棲": "living together", "片想い": "unrequited love",
    },
}


# サーバーがテーマを決めなかった回は LLM が選んで書くので、括弧の例示を落とした
# 短縮形（「食べ物」「旅行」）が返る。完全一致だけだとそこが日本語のまま残る。
_TOPIC_HEADS_EN: dict[str, str] = {
    topic.split("（")[0]: label for topic, label in TOPIC_LABELS_EN.items()
}


def _localize_topic(topic: str) -> str:
    label = TOPIC_LABELS_EN.get(topic)
    if label is not None:
        return label
    return _TOPIC_HEADS_EN.get(topic.split("（")[0], topic)


def localize_context(context: dict | None, lang: str) -> dict | None:
    """context の軸ラベルを訳文の言語に合わせる。

    ja はそのまま返す。en は既知の日本語ラベルだけ差し替え、未知の値
    （LLM が自由記述する emotion・usage_scenarios や、既に英語のもの）は触らない。
    冪等なので、英語化済みの例文にもう一度かけても壊れない。
    """
    if not isinstance(context, dict) or lang == DEFAULT_LANG:
        return context
    if lang != "en":
        return context

    topic = context.get("topic")
    localized = dict(context)
    if isinstance(topic, str):
        localized["topic"] = _localize_topic(topic)
    style = context.get("style")
    if isinstance(style, str):
        localized["style"] = STYLE_LABELS_EN.get(style, style)
    sub_theme = context.get("subTheme")
    if isinstance(sub_theme, str) and isinstance(topic, str):
        localized["subTheme"] = SUB_THEME_LABELS_EN.get(topic, {}).get(
            sub_theme, sub_theme
        )
    time_frame = context.get("timeFrame")
    if isinstance(time_frame, str):
        localized["timeFrame"] = TIME_FRAME_LABELS_EN.get(time_frame, time_frame)
    return localized

# ─── 述べ方（モダリティ）は 2026-08-06 に削除 ───
# 断定/推量/伝聞/確認 の4値を抽選していたが、確定済みの key_word に後付けすると
# 無理な命題を作った（×ได้ยินว่าโรงแรมจองอีกห้อง ＝「ホテルが予約する」）。
# 述べ方の行を外して生成すると明らかに自然になる一方、น่าจะ/คง/ได้ยินว่า は
# 14文中1文まで落ちる。まず単調さの度合いを実測するため外してみる。



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
            # 訳出方針はプロンプト側（訳文ルール）に集約する。
            "description": "例文の日本語訳",
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
                    "description": "使用場面の説明。日本語で、50文字以内（タイ語・英語不可）。",
                },
                "cultural_notes": {
                    "type": "string",
                    "description": "文化的な補足情報。日本語で、50文字以内（タイ語・英語不可）。",
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
    # 2026-08-06: 文体の自動抽選を止めて LLM に選ばせた結果、返る値が
    # 「丁寧語 / 日常会話 / 中立 / カジュアル / 日常的な話し言葉」と揺れた。
    # 履歴画面の表示と集計に使うので、既存の STYLES に分類させて表記を揃える。
    "style": {
        "type": "string",
        "enum": STYLES,
        "description": "実際に書いた文体を最も近いものに分類する",
    },
    "emotion": {"type": "string", "description": "感情・トーン（例: 中立）"},
}


# ─── 訳文言語で差し替える description ───
# フィールド名は japanese_translation のまま（DB列・Firestore・Dartモデルに広く
# 散っており、改名コストが見合わない）。en では名前に引きずられないよう
# description で正面から否定する。
_SCHEMA_DESCRIPTIONS_EN = {
    "japanese_translation": (
        "例文の英訳。フィールド名は japanese だが必ず英語で書くこと（日本語不可）"
    ),
    "word_breakdown": "例文を構成する各単語と英語の意味。最大20件。",
    "meaning": "単語の意味を必ず英語で記述すること（日本語不可）",
    "note": "用法・ニュアンス・類語との違い（英語、50語以内）",
    # context は詳細画面にそのまま表示される。ここを訳し忘れると英語UIの中で
    # 「使用シーン」「文化的背景」だけ日本語で出る。
    "usage_scenarios": "使用場面の説明。英語で、25語以内（タイ語・日本語不可）。",
    "cultural_notes": "文化的な補足情報。英語で、25語以内（タイ語・日本語不可）。",
}

# LLM に生成させる context フィールドの en 版 description。
#
# topic と style は識別子（履歴画面の集計キー）なので**日本語のまま返させる**。
# クライアントが generation_labels.dart で表示だけ訳す。ここを英語にすると、
# サーバーがテーマを決めた回は日本語・LLM が選んだ回は英語となり、同じ画面の
# 同じ項目で言語が混ざる（2026-08-07 に実測して差し戻した）。
# emotion だけは自由記述でそのまま表示されるので英語にする。
_CONTEXT_DESCRIPTIONS_EN = {
    "emotion": "感情・トーン（英語で。例: neutral）",
}


def _apply_lang_descriptions(schema: dict) -> dict:
    """en 用に description を差し替える（構造は変えない）。"""
    props = schema["properties"]
    props["japanese_translation"]["description"] = _SCHEMA_DESCRIPTIONS_EN[
        "japanese_translation"
    ]
    props["word_breakdown"]["description"] = _SCHEMA_DESCRIPTIONS_EN["word_breakdown"]
    props["word_breakdown"]["items"]["properties"]["meaning"]["description"] = (
        _SCHEMA_DESCRIPTIONS_EN["meaning"]
    )
    props["target_notes"]["items"]["properties"]["note"]["description"] = (
        _SCHEMA_DESCRIPTIONS_EN["note"]
    )
    context_props = props["context"]["properties"]
    for name in ("usage_scenarios", "cultural_notes"):
        context_props[name]["description"] = _SCHEMA_DESCRIPTIONS_EN[name]
    return schema


def build_response_schema(
    ask_context_fields: tuple[str, ...] = (), lang: str = DEFAULT_LANG
) -> dict:
    """リクエストごとのレスポンススキーマを組み立てる。

    Args:
        ask_context_fields: LLM に生成させる context フィールド名。
            プロンプトで値を指定しなかったものだけを渡すこと。
        lang: 訳文の言語。en では description のみ差し替える。

    Returns:
        dict: RESPONSE_JSON_SCHEMA のコピー。指定フィールドを context に追加済み。
    """
    if not ask_context_fields and lang == DEFAULT_LANG:
        return RESPONSE_JSON_SCHEMA

    schema = copy.deepcopy(RESPONSE_JSON_SCHEMA)
    if lang != DEFAULT_LANG:
        schema = _apply_lang_descriptions(schema)
    context = schema["properties"]["context"]
    for name in ask_context_fields:
        field = _CONTEXT_GENERATABLE_FIELDS.get(name)
        if field is None:
            continue
        field = dict(field)
        if lang != DEFAULT_LANG and name in _CONTEXT_DESCRIPTIONS_EN:
            field["description"] = _CONTEXT_DESCRIPTIONS_EN[name]
        context["properties"][name] = field
        context["required"].append(name)
    return schema
