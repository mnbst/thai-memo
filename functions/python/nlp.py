"""
「まいにちタイ語」アプリ — 自然言語処理（NLP）モジュール

このファイルでは、OpenAI が生成したタイ語例文に対して、
PyThaiNLP を使用した後処理（エンリッチメント）を行います。

主な処理:
  1. 音節分割（subword_tokenize）: タイ語の単語を音節単位に分割
  2. 発音変換（thai_to_pronunciation）: タイ文字を声調記号付きローマ字に変換
  3. 品詞タグ付け（pos_tag）: 各単語の品詞を判定し日本語ラベルを付与

PyThaiNLP はタイ語の自然言語処理ライブラリで、形態素解析・品詞タグ付け・
音節分割など多くの機能を提供します。
"""

# PyThaiNLP の品詞タグ付け（pos_tag）と音節分割（subword_tokenize）。
# pythainlp から直接 import すると使わないサブモジュールまで読み込まれてコールド
# スタートが伸びるため、必要な分だけロードするラッパを経由する。
try:
    from .pythainlp_fast import pos_tag, subword_tokenize
except ImportError:
    from pythainlp_fast import pos_tag, subword_tokenize

# 発音変換モジュール（タイ文字→声調記号付きローマ字）
try:
    from .pronunciation import thai_to_pronunciation
except ImportError:
    from pronunciation import thai_to_pronunciation

# ─── 品詞タグの英語→日本語マッピング辞書 ───
# PyThaiNLP が返す Universal Dependencies 準拠の品詞タグ（英語）を
# アプリのUI表示用に日本語に変換するためのマッピング
_POS_TAG_MAP = {
    "NOUN": "名詞",
    "VERB": "動詞",
    "ADJ": "形容詞",
    "ADV": "副詞",
    "PRON": "代名詞",
    "DET": "限定詞",
    "ADP": "前置詞",
    "AUX": "助動詞",
    "CCONJ": "接続詞",      # 等位接続詞（例: และ = そして）
    "SCONJ": "接続詞",      # 従属接続詞（例: เพราะ = なぜなら）
    "PART": "助詞",          # 助詞（例: ครับ、ค่ะ）
    "INTJ": "感嘆詞",
    "NUM": "数詞",
    "PROPN": "固有名詞",
    "PUNCT": "句読点",
    "CLF": "類別詞",         # タイ語特有の品詞（例: คน = 人を数える類別詞）
    "NEG": "否定詞",         # 否定を表す語（例: ไม่ = 〜ない）
}


# ─── 形容詞辞書 ───
# scripts/build_adjective_dict.py が生成する。未生成でも動作するよう
# import 失敗時は空集合にフォールバックする（タガーの判定に委ねる）。
try:
    from pos_adjectives import ADJECTIVES
except ImportError:  # pragma: no cover - 辞書未生成時のみ
    try:
        from .pos_adjectives import ADJECTIVES  # type: ignore[no-redef]
    except ImportError:
        ADJECTIVES: frozenset[str] = frozenset()  # type: ignore[misc,no-redef]


# ─── 閉じた語クラスの品詞辞書 ───
# タイ語の機能語（終助詞・代名詞・指示詞など）は有限個だが、
# PyThaiNLP の perceptron タガーはこれらを未知語として NOUN に誤判定する。
# 学習アプリでは出現頻度が非常に高いため、辞書で確定させる。
# 複数の品詞を取りうる語（ได้ / ที่ / ก็ 等）は曖昧なのであえて含めず、
# タガーの文脈判定に委ねる。
_POS_OVERRIDE: dict[str, str] = {
    # 終助詞・文末詞
    "ครับ": "PART", "ค่ะ": "PART", "คะ": "PART", "ขา": "PART",
    "นะ": "PART", "น่ะ": "PART", "สิ": "PART", "ซิ": "PART",
    "ล่ะ": "PART", "เหรอ": "PART", "หรอ": "PART",
    "จ๊ะ": "PART", "จ้ะ": "PART", "จ้า": "PART",
    "ไหม": "PART", "มั้ย": "PART",
    "อ่ะ": "PART", "อะ": "PART", "ฮะ": "PART", "แหละ": "PART",
    "เถอะ": "PART", "วะ": "PART", "ว่ะ": "PART", "ยัง": "PART",
    # 疑問詞
    "เท่าไหร่": "PRON", "เท่าไร": "PRON", "อะไร": "PRON", "ใคร": "PRON",
    "ยังไง": "ADV", "ไง": "ADV", "ได้ไง": "ADV", "อย่างไร": "ADV",
    "ทำไม": "ADV", "เมื่อไหร่": "ADV", "ที่ไหน": "ADV",
    # 相互・共同を表す標識（「一緒に〜する」）
    "กัน": "ADV",
    # 終助詞の連結（LLM が1トークンで返すことがある）
    "นะครับ": "PART", "นะคะ": "PART", "ครับผม": "PART",
    "ล่ะครับ": "PART", "ล่ะคะ": "PART",
    # 代名詞
    "ผม": "PRON", "ฉัน": "PRON", "ดิฉัน": "PRON", "หนู": "PRON",
    "กู": "PRON", "มึง": "PRON", "คุณ": "PRON", "เธอ": "PRON",
    "เรา": "PRON", "เขา": "PRON", "มัน": "PRON", "ท่าน": "PRON",
    "พวกเรา": "PRON", "พวกเขา": "PRON",
    # 指示詞
    "นี้": "DET", "นั้น": "DET", "โน้น": "DET",
    "อันนี้": "DET", "อันนั้น": "DET",
    "ตัวนี้": "DET", "ตัวนั้น": "DET",
    "จานนี้": "DET",
    # 感嘆詞
    "โอ้โห": "INTJ", "ว้าว": "INTJ", "อุ๊ย": "INTJ",
    "เฮ้ย": "INTJ", "โอ๊ย": "INTJ", "ว้า": "INTJ", "เอ๊ะ": "INTJ",
    # 否定
    "ไม่": "NEG", "ไม่ได้": "NEG", "อย่า": "NEG", "ห้าม": "NEG",
    # 程度の副詞
    "มาก": "ADV", "จัง": "ADV", "เลย": "ADV", "จังเลย": "ADV",
    "หน่อย": "ADV", "นิดหน่อย": "ADV", "ที่สุด": "ADV",
    # 助動詞
    "จะ": "AUX", "ต้อง": "AUX", "ควร": "AUX",
    "อาจ": "AUX", "คง": "AUX", "กำลัง": "AUX", "เคย": "AUX",
}


def _tag_words(words: list[str]) -> dict[int, str]:
    """単語リストに品詞タグ（UDタグ）を付与する。

    優先順位:
      1. _POS_OVERRIDE — 機能語の確定辞書
      2. ADJECTIVES — 形容詞辞書。タイ語の形容詞は文法的には状態動詞だが、
         コーパスによって ADJ/VERB/ADV に割れるため「形容詞」に統一する
      3. unigram/tud — 辞書ベース。未知語には空文字を返すため誤判定が少ない
      4. perceptron/orchid_ud — 上記で埋まらない語のフォールバック

    perceptron を単独で使うと未知語をすべて NOUN と推測してしまうため、
    精度の高い順に段階的に適用する。

    Returns:
        dict[int, str]: インデックス → 日本語の品詞名
    """
    result: dict[int, str] = {}
    if not words:
        return result

    unresolved = {}
    for i, word in enumerate(words):
        tag = _POS_OVERRIDE.get(word)
        if tag:
            result[i] = _POS_TAG_MAP.get(tag, tag)
        elif word in ADJECTIVES:
            result[i] = "形容詞"
        else:
            unresolved[i] = word

    if not unresolved:
        return result

    # 2. unigram: 未知語には空文字が返るので、埋まった分だけ採用する
    idxs = list(unresolved)
    targets = [unresolved[i] for i in idxs]
    still: list[int] = []
    try:
        tags = pos_tag(targets, engine="unigram", corpus="tud")
        for i, tag_pair in zip(idxs, tags):
            tag = tag_pair[1] if len(tag_pair) >= 2 else ""
            if tag:
                result[i] = _POS_TAG_MAP.get(tag, tag)
            else:
                still.append(i)
    except Exception as e:
        print(f"NLP POS (unigram) failed: {e}")
        still = idxs

    if not still:
        return result

    # 3. perceptron: 最後の手段。文脈判定のため全単語を渡す
    try:
        tags = pos_tag(words, engine="perceptron", corpus="orchid_ud")
        for i in still:
            if i < len(tags) and len(tags[i]) >= 2:
                result[i] = _POS_TAG_MAP.get(tags[i][1], tags[i][1])
    except Exception as e:
        print(f"NLP POS (perceptron) failed: {e}")

    return result


def segment_syllables(word: str) -> list[str]:
    """タイ語の単語を音節単位に分割する。

    PyThaiNLP の辞書ベースサブワードトークナイザを使用して、
    タイ語の単語を音節のリストに分解する。

    例: "สวัสดี" → ["สวัส", "ดี"]

    Args:
        word: 分割対象のタイ語単語

    Returns:
        list[str]: 音節のリスト
    """
    return subword_tokenize(word, engine="dict")


def get_pos_japanese(word: str) -> str:
    """タイ語の単語の品詞を日本語で返す。

    機能語辞書と PyThaiNLP を組み合わせて品詞を判定し、日本語ラベルに変換する。
    判定順序は _tag_words を参照。

    例: "กิน"（食べる）→ "動詞"

    Args:
        word: 品詞を判定するタイ語の単語

    Returns:
        str: 日本語の品詞名。マッピングに該当しない場合は "その他" を返す
    """
    return _tag_words([word]).get(0, "その他")


def enrich_with_nlp(sentence: dict) -> dict:
    """AI が生成した例文データに NLP 後処理を適用する。

    word_breakdown 内の各単語に対して以下の情報を追加する:
      - syllables: 音節分割結果のリスト
      - pronunciation: 声調記号付きローマ字表記
      - grammatical_role: 日本語の品詞名

    また、各単語の発音を結合して文全体の発音（pronunciation）も生成する。

    各処理は独立しており、一部が失敗しても他の処理は続行される。
    エラーはログに出力されるが、例外は再送出しない。

    Args:
        sentence: AI から返された例文データの辞書。
                  "word_breakdown" キーに単語リストを含む。

    Returns:
        dict: NLP情報が追加された例文データ（引数と同じオブジェクトを返す）
    """
    word_breakdowns = sentence.get("word_breakdown", [])
    words = [wb.get("word", "") for wb in word_breakdowns]

    # 品詞タグ付け: 辞書 → unigram → perceptron の順で段階的に判定する
    pos_map = _tag_words(words)

    # 各単語の発音を蓄積し、最後に文全体の発音を構築する
    word_pronunciations = []

    for i, wb in enumerate(word_breakdowns):
        word = wb.get("word", "")

        # 音節分割: 単語を音節のリストに分解
        try:
            wb["syllables"] = segment_syllables(word)
        except Exception as e:
            print(f"NLP syllables failed for '{word}': {e}")

        # 発音変換: タイ文字を声調記号付きローマ字に変換
        try:
            pron = thai_to_pronunciation(word)
            wb["pronunciation"] = pron
            word_pronunciations.append(pron)
        except Exception as e:
            print(f"NLP pronunciation failed for '{word}': {e}")

        # 品詞: 一括タグ付けの結果を適用（失敗時はフォールバック）
        if i in pos_map:
            wb["grammatical_role"] = pos_map[i]
        else:
            try:
                wb["grammatical_role"] = get_pos_japanese(word)
            except Exception as e:
                print(f"NLP POS (fallback) failed for '{word}': {e}")

    # 各単語の発音をスペースで結合して文全体の発音を生成
    if word_pronunciations:
        sentence["pronunciation"] = " ".join(word_pronunciations)

    return sentence
