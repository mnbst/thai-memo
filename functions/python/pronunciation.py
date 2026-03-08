"""
「まいにちタイ語」アプリ — 発音変換モジュール

このファイルでは、タイ語テキストを声調記号付きローマ字（発音表記）に変換します。

変換フロー:
  1. TLTK ライブラリでタイ文字を IPA（国際音声記号）に変換
  2. IPA の各音節を独自のローマ字表記に変換
  3. 声調番号を Unicode 結合ダイアクリティカルマーク（声調記号）に変換
  4. 音節をハイフンで結合して最終的な発音表記を生成

変換例:
  - "สวัสดี"  → "sa-wat-dii"
  - "ไม่รู้"   → "mai-ruu" （声調記号付き）
  - "ขอบคุณ" → "khɔ̀ɔp-khun"

タイ語の声調（5種類）:
  1. 平声（สามัญ）  — 記号なし
  2. 低声（เอก）    — `（グレーブ）
  3. 下降声（โท）   — ^（サーカムフレックス）
  4. 高声（ตรี）    — '（アキュート）
  5. 上昇声（จัตวา） — ˇ（キャロン）
"""

import re
import unicodedata

# TLTK（Thai Language Toolkit）: タイ語テキストを IPA に変換するライブラリ
import tltk.nlp

# ─── 声調番号から Unicode 結合記号へのマッピング ───
# TLTK が出力する声調番号（1〜5）を、ローマ字の母音に付加する
# Unicode 結合ダイアクリティカルマーク（combining diacritical marks）に変換する
_TONE_MARKS = {
    "1": "",  # mid (สามัญ) — 平声: 記号なし
    "2": "\u0300",  # low (เอก): à — 低声
    "3": "\u0302",  # falling (โท): â — 下降声
    "4": "\u0301",  # high (ตรี): á — 高声
    "5": "\u030c",  # rising (จัตวา): ǎ — 上昇声
}

# ─── IPA → ローマ字 変換テーブル ───
# TLTK が出力する IPA 表記を、学習者にわかりやすいローマ字表記に変換する。
# 変換順序が重要: 長い文字列を先にマッチさせる必要がある（例: "tɕʰ" を "t" より先に）
_IPA_TO_ROMAN: list[tuple[str, str]] = [
    # プレースホルダ退避: ช(cʰ)→CH, จ(tɕ/c)→J（後で j→i と衝突しないように）
    # タイ語の ช（チョー・チャーン）と จ（ジョー・ジャーン）の子音を
    # 一時的に大文字プレースホルダに変換して、後続の変換ルールとの衝突を回避
    ("tɕʰ", "CH"),
    ("cʰ", "CH"),
    ("tɕ", "J"),
    ("c", "J"),
    # 有気音（息を伴う子音）: kh, th, ph
    ("kʰ", "kh"),
    ("tʰ", "th"),
    ("pʰ", "ph"),
    # 鼻音・その他の子音
    ("ŋ", "ng"),   # ง（ンゴー）: 日本語の「ん」に近い鼻音
    ("ɲ", "ny"),   # ญ（ヨー・イン）: 「にゃ」に近い音
    ("ʔ", ""),     # 声門閉鎖音: 表記なし（日本語にも存在するが意識されない音）
    # 母音の変換（長母音は二重表記、例: aa, ii, uu）
    ("ɯː", "ʉʉ"),  # อือ（長母音）
    ("ɯ", "ʉ"),     # อึ（短母音）
    ("ɛː", "ɛɛ"),   # แอ（長母音）
    ("ɛ", "ɛ"),      # แอ（短母音）
    ("ᴐː", "ɔɔ"),   # ออ（長母音）
    ("ᴐ", "ɔ"),      # ออ（短母音）
    ("ɤː", "əə"),   # เออ（長母音）
    ("ɤ", "ə"),      # เออ（短母音）
    ("aː", "aa"),    # อา（長母音）
    ("iː", "ii"),    # อี（長母音）
    ("uː", "uu"),    # อู（長母音）
    ("eː", "ee"),    # เอ（長母音）
    ("oː", "oo"),    # โอ（長母音）
    # j は _convert_syllable 内で処理（母音後→i、それ以外→y）
    # CH, J のプレースホルダ復元も _convert_syllable 内で実行
]

# ─── 母音文字の集合 ───
# 声調記号を付加する位置（最初の母音）を特定するために使用
_VOWELS = set("aeiouɔɛəʉ")


def _add_tone(syllable: str, tone: str) -> str:
    """ローマ字音節に声調記号を付加する。

    音節内の最初の母音文字を見つけ、その直後に
    Unicode 結合ダイアクリティカルマークを挿入する。

    例: _add_tone("khun", "4") → "khún"（高声）

    Args:
        syllable: 声調記号なしのローマ字音節
        tone: 声調番号（"1"〜"5"）

    Returns:
        str: 声調記号付きのローマ字音節。平声（"1"）の場合はそのまま返す
    """
    mark = _TONE_MARKS.get(tone, "")
    if not mark:
        return syllable
    # 最初の母音文字を探し、その直後に声調記号を挿入
    for i, ch in enumerate(syllable):
        if ch in _VOWELS:
            return syllable[: i + 1] + mark + syllable[i + 1 :]
    return syllable


def _convert_syllable(ipa_syl: str) -> str:
    """IPA 表記の1音節をローマ字に変換する。

    処理手順:
      1. 末尾の声調番号を抽出
      2. IPA → ローマ字の変換テーブルを適用
      3. 半母音 j の処理（母音後→i、子音位置→y）
      4. プレースホルダの復元（CH→ch、J→j）
      5. 声調記号の付加

    例: "kʰun4" → "khún"

    Args:
        ipa_syl: TLTK が出力した IPA 表記の1音節（末尾に声調番号を含む場合がある）

    Returns:
        str: 声調記号付きのローマ字表記
    """
    # 末尾の数字を声調番号として抽出（デフォルトは平声 "1"）
    tone = "1"
    if ipa_syl and ipa_syl[-1].isdigit():
        tone = ipa_syl[-1]
        ipa_syl = ipa_syl[:-1]

    # IPA → ローマ字の変換テーブルを順に適用
    result = ipa_syl
    for ipa, roman in _IPA_TO_ROMAN:
        result = result.replace(ipa, roman)

    # 半母音 j の処理:
    # - 母音の後の j → i（二重母音を形成: aj→ai、oj→oi 等）
    # - それ以外の j → y（子音としての ย: ya、yo 等）
    # 母音後の j → i（二重母音: aj→ai 等）、それ以外の j → y（子音ย）
    result = re.sub(r"(?<=[aeiouɔɛəʉ])j", "i", result)
    result = result.replace("j", "y")

    # プレースホルダを最終的なローマ字に復元
    # CH → ch（ช: チョー・チャーン）、J → j（จ: ジョー・ジャーン）
    # プレースホルダ復元: CH→ch（ช）、J→j（จ）
    result = result.replace("CH", "ch").replace("J", "j")

    # 声調記号を付加して返す
    return _add_tone(result, tone)


def thai_to_pronunciation(thai_text: str) -> str:
    """タイ語テキストを声調記号付きローマ字（発音表記）に変換する。

    TLTK ライブラリでタイ文字を IPA に変換した後、
    独自のローマ字変換ロジックで学習者向けの発音表記を生成する。

    変換例:
      - "ไม่รู้" → "mâi-rúu"
      - "สวัสดี" → "sa-wàt-dii"
      - "ขอบคุณ" → "khɔ̀ɔp-khun"

    Args:
        thai_text: 変換対象のタイ語テキスト

    Returns:
        str: 声調記号付きのローマ字表記。音節はハイフンで区切られる。
             Unicode NFC 正規化済み。
    """
    # TLTK でタイ文字を IPA に変換し、文区切り記号を除去
    ipa = tltk.nlp.th2ipa(thai_text).replace("<s/>", "").strip()

    # IPA をピリオドで音節に分割（TLTK の出力形式）
    syllables = [s.strip() for s in ipa.split(".") if s.strip()]

    # 各音節をローマ字に変換し、ハイフンで結合
    # Unicode NFC 正規化: 結合文字（声調記号）と基底文字を正規化して
    # 文字列の一貫性を保証する
    return unicodedata.normalize(
        "NFC", "-".join(_convert_syllable(s) for s in syllables)
    )
