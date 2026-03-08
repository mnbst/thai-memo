"""
「まいにちタイ語」アプリ — 自然言語処理（NLP）モジュール

このファイルでは、Gemini AI が生成したタイ語例文に対して、
PyThaiNLP を使用した後処理（エンリッチメント）を行います。

主な処理:
  1. 音節分割（subword_tokenize）: タイ語の単語を音節単位に分割
  2. 発音変換（thai_to_pronunciation）: タイ文字を声調記号付きローマ字に変換
  3. 品詞タグ付け（pos_tag）: 各単語の品詞を判定し日本語ラベルを付与

PyThaiNLP はタイ語の自然言語処理ライブラリで、形態素解析・品詞タグ付け・
音節分割など多くの機能を提供します。
"""

# PyThaiNLP の品詞タグ付け機能（Universal Dependencies 準拠のタグセット）
from pythainlp.tag import pos_tag
# PyThaiNLP の音節分割機能（辞書ベースのサブワードトークナイザ）
from pythainlp.tokenize import subword_tokenize

# 発音変換モジュール（タイ文字→声調記号付きローマ字）
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

    PyThaiNLP の品詞タグ付け機能（perceptron エンジン、orchid_ud コーパス）を
    使用して品詞を判定し、日本語ラベルに変換する。

    例: "กิน"（食べる）→ "動詞"

    Args:
        word: 品詞を判定するタイ語の単語

    Returns:
        str: 日本語の品詞名。マッピングに該当しない場合は "その他" を返す
    """
    # perceptron エンジンと orchid_ud コーパスで品詞タグ付け
    tags = pos_tag([word], engine="perceptron", corpus="orchid_ud")
    if tags and len(tags[0]) >= 2:
        # 英語タグを日本語に変換（マッピングにない場合は英語タグをそのまま返す）
        return _POS_TAG_MAP.get(tags[0][1], tags[0][1])
    return "その他"


def enrich_with_nlp(sentence: dict) -> dict:
    """Gemini が生成した例文データに NLP 後処理を適用する。

    word_breakdown 内の各単語に対して以下の情報を追加する:
      - syllables: 音節分割結果のリスト
      - pronunciation: 声調記号付きローマ字表記
      - grammatical_role: 日本語の品詞名

    また、各単語の発音を結合して文全体の発音（pronunciation）も生成する。

    各処理は独立しており、一部が失敗しても他の処理は続行される。
    エラーはログに出力されるが、例外は再送出しない。

    Args:
        sentence: Gemini API から返された例文データの辞書。
                  "word_breakdown" キーに単語リストを含む。

    Returns:
        dict: NLP情報が追加された例文データ（引数と同じオブジェクトを返す）
    """
    # 各単語の発音を蓄積し、最後に文全体の発音を構築する
    word_pronunciations = []

    for wb in sentence.get("word_breakdown", []):
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

        # 品詞タグ付け: 単語の文法的役割を日本語で付与
        try:
            wb["grammatical_role"] = get_pos_japanese(word)
        except Exception as e:
            print(f"NLP POS failed for '{word}': {e}")

    # 各単語の発音をスペースで結合して文全体の発音を生成
    if word_pronunciations:
        sentence["pronunciation"] = " ".join(word_pronunciations)

    return sentence
