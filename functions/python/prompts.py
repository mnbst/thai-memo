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
    TOPIC_SUB_THEMES,
    TOPICS,
)
from embeddings import (
    find_best_sub_theme,
    get_emotion_similarity_weights,
    get_style_similarity_weights,
    get_topic_option_similarity_weights,
)
from themes.bl_drama import build_drama_prompt_section
from word_classes import CLASSES as WORD_CLASSES
from word_classes import classify_all, requires_formal_politeness

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


# ─── 効果測定のため SYSTEM_PROMPT_PREMIUM から除外中（2026-08-03） ───
# 200文の生成ログで「一度も発火しない／抽象的で判定不能／偏りの原因」と判断した行。
# 品質が落ちたら戻す。
# - 動詞中心に組み立てる。直訳構文禁止
# - 主題を前置したら、主題と動詞が自然に共起し文全体が一息で流れるか確認する。崩れるなら通常語順に戻す
# - คุณคือ〜多用禁止→感情はทำให้〜、説明はเป็นคนที่〜
# - 場所→ที่นี่、状況→แบบนี้（カジュアル: งี้）
# - 会話はนะ/ดูで柔らかく
# - ได้+動詞は経験・機会として使用
# - 英語由来語は語尾・補足で自然に（โอเคแล้วนะ等）
# --- 第3次除外（導入後も違反が続き、無効と確認） ---
# - 動詞+ได้+形容詞と並べない。結果は〜แล้ว+形容詞で表す（×กินได้อร่อย →○กินแล้วอร่อย／×เดินได้สบาย →○เดินแล้วสบาย）
# --- 第2次除外（発火ゼロの確認のため） ---
# - 過去は〜แล้ว/ตอน〜優先。冗長なเมื่อ〜ก็〜は避ける
# - 指示・依頼はช่วย〜หน่อย/รบกวน〜หน่อย優先
# - 英語直訳の比較・強調構文は禁止（×สวยเกินกว่าอะไรที่เคยพบเห็น →○สวยกว่าที่ไหนที่เคยไปมา／×เงียบอย่างที่ไม่เคยเป็น →○เงียบกว่าปกติมาก）

# ─── 末尾配置の制約（system prompt では守られなかったもの） ───
# 語彙レベルの禁止は system prompt では守られなかった（sample_sentences.py で複数回確認）。
# 長い可変コンテキストの後ろに置いた指示のほうが効く、という仮説の検証のため
# build_prompt_with_context の最終ブロックへ移設している。効果が無ければ元へ戻す。
# 丁寧さ・テーマが確定しているものは、その条件のときだけ入れる（常時入れると
# ルール全体が薄まり、フォーマル時は「硬語禁止」自体が矛盾になるため）。
_ALWAYS_RULES = [
    "動詞と目的語・副詞の定型の組み合わせを崩さない"
    "（×รอเดี๋ยว →○รอแป๊บนึง／観光で見る意味の×ไปดูงาน →○ไปดู／×แพ้เกมทุกอย่าง →○แพ้ทุกเกม／"
    "買えない意味の×เอาไม่ได้ →○ซื้อไม่ได้）。"
    "同じ働きの副詞を重ねない（×ไม่มี…บ้างเลย →○ไม่มี…เลย／×ยัง…อีก →○ยัง…อยู่）",
    "japanese_translation に thai_text へ無い語句を足さない。推測した理由・感情・評価は書かない"
    "（×「静かすぎる」→「心配」／×「車が少ない」→「快適」／×「もう前とは違う」→「楽しくない」）",
    "応答・あいさつ表現（ไม่เป็นไร/ขอบคุณ/ขอโทษ/ได้เลย等）は、対応する状況を先に同じ文中へ置いてから使う"
    "（×แดดร้อน กลัวผิวเสีย ไม่เป็นไรค่ะ →○ลืมทาครีมอีกแล้ว ไม่เป็นไร เดี๋ยวซื้อใหม่）",
]

# 丁寧さがフォーマル、または文体がニュース記事体・物語文学体のときは外す。
# その場合は硬語こそが正解になり、禁止すると ได้ 落ちなどの非文を招く（実測）。
_CASUAL_ONLY_RULES = [
    "สามารถ〜ได้ は使わない。〜ได้ だけで書く（×ทัวร์นี้สามารถเข้าได้ →○ทัวร์นี้เข้าได้）",
    "書き言葉の硬い語・名詞句・文語の副詞を会話文に使わない"
    "（×ท่าน →○คุณ／×ต้องการ →○อยาก／×ให้บริการ →○เปิด／×เป็นที่น่าตกใจ →○ตกใจเลย／"
    "×〜นัก →○〜มาก／×การทัวร์นี้ →○ทัวร์นี้／×พลังของพายุนี้รุนแรงมาก →○พายุนี้แรงมาก）",
]

# 場所の移動が出るテーマでだけ効く。
_PLACE_TOPIC_RULES = [
    "移動動詞の方向を場所と合わせる。ที่นี่＝話者のいる場所→มา、ที่นั่น＝離れた場所→ไป"
    "（×เคยมาที่นี่ไหม ไปได้ง่ายนะ →○เคยมาที่นี่ไหม มาได้ง่ายนะ）",
]

# 恋愛系テーマでだけ効く。
_ROMANCE_TOPIC_RULES = [
    "性的・露骨な恋愛描写は禁止。健全な範囲に留める",
]

_HARD_REGISTER_STYLES = ("ニュース", "物語", "丁寧語")


def build_register_constraint(politeness: str, style: str, topic: str) -> str:
    """丁寧さ・文体・テーマで出し分けた【最後に確認】ブロックを返す。"""
    rules = list(_ALWAYS_RULES)
    hard_ok = politeness == POLITENESS_LEVELS[0] or style.startswith(
        _HARD_REGISTER_STYLES
    )
    if not hard_ok:
        rules = _CASUAL_ONLY_RULES + rules
    if topic in (TOPICS[2], TOPICS[6]):  # 旅行 / 交通
        rules += _PLACE_TOPIC_RULES
    if topic in (TOPICS[14], TOPICS[15]):  # 恋愛 / タイBLドラマ
        rules += _ROMANCE_TOPIC_RULES
    body = "\n".join(f"{i}. {r}" for i, r in enumerate(rules, 1))
    return f"【最後に確認】\n{body}"


# ─── 語クラス別ブロック（該当時のみ末尾に足す） ───
# 機能語が key_word に来ると、LLM がその語を主語・主動詞に据えて非文を作る失敗が
# 支配的だった（2026-08-03 実測: 該当8語で 5/8 が破綻）。
# 常時のシステムプロンプトに足すとルール全体が薄まるため、該当時だけ末尾に付ける。
# 手順3の「削っても文が成立するか」が、機能語かどうかの機械的な判定になる。
FUNCTION_WORD_STEPS = (
    "この語は文の主役にならない。次の順で作る。\n"
    "1. ターゲット語を使わずに、テーマに沿った自然な文をまず作る\n"
    "2. その文の中でこの語が自然に入る位置が1つあるならそこに入れる。無ければ手順1の文を作り直す\n"
    "3. 確認: ターゲット語を消しても文が成立するか。成立しないなら語に合わせて文を歪めている→1へ戻る\n"
    "この語の意味・用法を説明・例示するための文にしない"
    "（×มันถึงเวลาเที่ยงแล้วหรือคะ →○เที่ยงแล้วเหรอคะ หิวเลย）"
)


def build_word_class_constraint(target_words: list[str] | None) -> str:
    """ターゲット語のクラスに応じた末尾ブロックを組み立てる。

    未分類（内容語）だけなら空文字を返し、ブロック自体を付けない。
    """
    class_ids = classify_all(target_words)
    if not class_ids:
        return ""

    classes = [WORD_CLASSES[cid] for cid in class_ids]
    labels = "・".join(c["label"] for c in classes)
    lines = [f"【ターゲット語は{labels}】"]
    if any(c.get("function_word") for c in classes):
        lines.append(FUNCTION_WORD_STEPS)
    lines.extend(c["rule"] for c in classes if c.get("rule"))
    return "\n".join(lines)


SYSTEM_PROMPT_PREMIUM = """タイ語練習文を1つ生成。

# 優先順位（衝突したら上を優先、下は落としてよい）
ターゲット単語 ＞ 自然さ ＞ 難易度 ＞ テーマ・文体・丁寧さ・文法フォーカス・感情
ターゲット単語が硬い語（ท่าน等）なら、ルールを破らずその語が自然な場面（改まった場）へ文脈を寄せる。

# 構文ルール（最重要）

## ターゲット語の入れ方（最も壊れやすい）
- 入れるために語順を崩さない。動詞→目的語、名詞→修飾語→指示詞を保つ（×เช้านี้ตื่นเช้าพยายามไม่สำเร็จ →○เช้านี้พยายามตื่นเช้าแต่ไม่สำเร็จ）
- 現代の口語で通用する用法だけ。文語・古語・方言の用法しかないなら文脈ごと変える（×เจ้าทางนี้สวย →○ร้านเจ้านี้อร่อยกว่าเจ้าอื่น）
- 独立した意味で使用（複合語の一部のみNG。畳語は除く）
- 動詞は具体的な目的語と組ませる。汎用の埋め草（เรื่อง/สิ่ง/อะไร）で埋めない（×ปกป้องเรื่องนั้น →○ปกป้องความลับ）

## 語順・文の構成
- 主題優勢。既知の話題を文頭の主題に置き、英語的SVOを避ける（×เราจะใช้รายงานนี้พรุ่งนี้ได้ไหม →○รายงานนี้พรุ่งนี้ใช้ได้ไหม）
- ただし主題が直後の動詞の主語と誤読される配置は禁止。特に心理・知覚動詞（คิด/รู้/นึก/รู้สึก）の前に場所・物を置かない（×ร้านนี้ไม่รู้เลยว่าอร่อยขนาดนี้ →○ไม่รู้เลยว่าร้านนี้จะอร่อยขนาดนี้）
- 主題を代名詞で受け直さない（×พี่น้องคู่นี้พวกเขาดูแลกันได้ดี →○พี่น้องคู่นี้ดูแลกันได้ดี）
- 状況の提示だけで終わらない。評価・感情・意向まで含めて完結（×พายุมาแบบนี้ →○พายุมาแบบนี้ คงไปไหนไม่ได้）
- 2節の並置は自然だが、両者の関係が「時間の順序／原因・理由／逆接／条件」のどれか1つに言えるときだけ。言えないなら1節で終える（×ฝนตกหนักขนาดนี้ ไม่เข้าใจเลย ／○ฝนตกแล้ว กลับก่อนดีกว่า）
- 接続詞（เพราะ/เพื่อ/แล้ว）は必要なときだけ。無理に繋がない

## 人称・指示
- 人称の一貫性。短い会話でผม/กู・คุณ/มึง・เขาを無根拠に混ぜない
- 指示対象が未確立の第三者（เขา等）を主語にしない（×มึงจะให้กูทำ แต่เขาไม่สนใจ →○...แต่กูไม่สนใจ）

## 否定
- ไม่+กำลังは非文→ไม่ได้〜อยู่（×กูไม่กำลังทำงานอยู่ →○กูไม่ได้ทำงานอยู่）
- ยัง+ไม่+形容詞は非文→ไม่ค่อย〜（×เสื้อยังไม่หนา →○เสื้อไม่ค่อยหนา）
- ไม่ได้〜แค่นี้は「この程度ではない」。「〜だけではない」はไม่ได้มีดีแค่〜
- 否定文で形容詞の後ろにดีを付けない。〜ดีは肯定の軽い感嘆専用（×ไม่ได้สะดวกดี →○ไม่ได้สะดวก）
- นึกไม่ถึง/ไม่คิดว่าの補文はจะ〜ขนาดนี้を伴う（×นึกไม่ถึงเลยว่าหนักมาก →○นึกไม่ถึงเลยว่าจะหนักขนาดนี้）

# 訳文ルール（japanese_translation）
原則: thai_textにある語だけを訳す。事実・感情・評価・理由・意図を足さない。補ってよいのは接続関係・助詞・語順・訳語の選択のみ。

- 自然で簡潔な日本語。時制はタイ語と一致。主語・目的語の対応を正確に（誰が誰を何を）
- 指示されたテーマ・サブテーマ・感情の語そのものを訳文に書かない（×ที่นี่ไม่เล็ก→「ここのナイトマーケットは」→○「ここは」）
- 否定の作用域を変えない（ไม่ได้สวยแค่นี้＝×「良さは美しさだけではない」→○「この程度の美しさじゃない」）
- ครับ/ค่ะは丁寧さのみ。「ね」「よ」はนะ/สิ/เลย/เนี่ยが実際にある場合だけ
- 並置の論理関係は補ってよい。時間の順序→「〜してから」、原因・理由→「〜ので」、逆接→「〜けど」、条件→「〜なら」。どれとも判断できなければ補わず並置のまま訳す
- 強調・限定・反語は話し言葉の等価表現に。硬い直訳（「〜については」「何のために」）は禁止（×「私については」→○「私のこともね」）
- 複数語で1つの意味はまとまりで訳す（×เปิดให้บริการ→「サービス提供を開く」→○「営業する」）。word_breakdownは語単位のまま分ける
- 結果・状態のได้+形容詞を「〜できる」と直訳しない（×ทำได้ดี→「うまくできる」→○「うまくやれている」）。能力・可能のได้は「〜できる」でよい

# 出力ルール
- thai_text: 語ごとの分かち書きは禁止（NG: ฉัน กิน ข้าว）。節・句の区切りの空白は可
- word_breakdown: 出現順に全て。ターゲット単語は独立エントリ。人称代名詞は性別・丁寧度を注記（例: ผม→「私（男性・丁寧）」）
- target_notes: ターゲット単語のみ。用法・類語との違い
- スペルミス厳禁: เธอをเธと書かない。母音-อを落とさない

本プロンプト中の×例・○例は書き方の説明であり出力候補ではない。そのまま／語を1つ替えただけで出さない。

出力前確認:
1. thai_text を語ごとに分かち書きしていないか
2. ターゲット単語が word_breakdown に独立エントリであるか
3. 2節を並置したなら、その関係を時間／原因／逆接／条件のどれか1つで言えるか。言えなければ1節に削る
4. japanese_translation の各文節が thai_text のどの語に対応するか言えるか。対応先の無い語句は削る
5. japanese_translation をタイ語に戻して同じ意味になるか（特に否定・限定・程度）
6. 上の例文の焼き直しになっていないか"""


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
        if requires_formal_politeness(target_words):
            # 書き言葉の語がターゲットのときは丁寧さを抽選しない。
            # カジュアルで確定するとその語の置き場所が無くなる。
            politeness = POLITENESS_LEVELS[0]
        elif topic == TOPICS[15]:
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

    # ブロックは "\n\n" で連結する。drama 未適用時に空行だけが残らないよう、
    # 空のブロックはリストに積まない。
    sections: list[str] = []
    if target_words:
        words_str = ", ".join(target_words)
        sections.append(
            "【最優先】以下のタイ語単語を必ず含めてください:\n"
            f"<target_words>\n{words_str}\n</target_words>"
        )
    if drama_context:
        sections.append(drama_context.strip())
    sections.append(
        f"""【必須】難易度:
- 語彙レベル: {diff["label"]}（{diff["vocab_hint"]}）
- 長さ: {diff["length"]}"""
    )
    if drama_required:
        sections.append(drama_required.strip())
    elements = (
        f"{topic_line}{sub_theme_line}{style_line}{politeness_line}"
        f"{grammar_line}{emotion_line}"
    )
    if elements.strip():
        sections.append(
            "【可能な限り反映】以下の要素を、自然なタイ語になる範囲で取り入れてください。"
            "上位の指示と衝突する場合は、この要素を落としてください。\n"
            f"{elements.rstrip()}"
        )

    # 語彙レジスタ制約は末尾に置く（system prompt では守られなかったため）。
    if prompt_is_premium:
        sections.append(build_register_constraint(politeness, style, topic))

    # 語クラス別の指示は最末尾（該当するクラスが無ければ付かない）。
    word_class_block = build_word_class_constraint(target_words)
    if word_class_block:
        sections.append(word_class_block)

    return "\n\n".join(sections), context
