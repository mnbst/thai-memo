"""pronunciation変換とPOSタグのテスト"""

from pathlib import Path
import sys

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from nlp import get_pos_japanese
from pronunciation import thai_to_pronunciation


class TestPronunciation:
    """tltk IPA → 声調記号付きローマ字変換のテスト"""

    @pytest.mark.parametrize(
        "thai, expected",
        [
            ("ไม่", "mâi"),
            ("รู้", "rúu"),
            ("สิ", "sì"),
            ("กัน", "kan"),
            ("กิน", "kin"),
            ("ใช้", "chái"),
            ("ให้", "hâi"),
            ("มาก", "mâak"),
            ("ครับ", "khráp"),
        ],
    )
    def test_single_word(self, thai: str, expected: str) -> None:
        assert thai_to_pronunciation(thai) == expected

    @pytest.mark.parametrize(
        "thai, expected",
        [
            ("สวัสดี", "sà-wàt-dii"),
            ("ขอบคุณ", "khɔ̀ɔp-khun"),
            ("เหมือน", "mʉ̌ʉan"),
            ("สุดท้าย", "sùt-tháai"),
            ("คำตอบ", "kham-tɔ̀ɔp"),
            ("กรุงเทพฯ", "krung-thêep"),
        ],
    )
    def test_multi_syllable(self, thai: str, expected: str) -> None:
        assert thai_to_pronunciation(thai) == expected

    @pytest.mark.parametrize(
        "thai, expected",
        [
            ("ไม่รู้สิ", "mâi-rúu-sì"),
            ("ใช้ชีวิต", "chái-chii-wít"),
            # จ→j / ช→ch の区別
            ("จะ", "jà"),
            ("ใจ", "jai"),
            ("ใช่", "châi"),
            ("ไม่ใช่", "mâi-châi"),
            ("ดิฉัน", "dì-chǎn"),
            # ย→y の区別
            ("ยา", "yaa"),
            ("อยู่", "yùu"),
            ("อย่าง", "yàang"),
            ("ชีวิตในกรุงเทพฯ", "chii-wít-nai-krung-thêep"),
            ("ชีวิตในกรุงเทพฯ สนุกมาก", "chii-wít-nai-krung-thêep sà-nùk-mâak"),
        ],
    )
    def test_phrase(self, thai: str, expected: str) -> None:
        assert thai_to_pronunciation(thai) == expected

    def test_thai_abbreviation_mark_is_silent(self) -> None:
        assert thai_to_pronunciation("ฯ") == ""

    @pytest.mark.parametrize(
        "thai, expected",
        [
            ("ไปๆมาๆ", "pai-pai maa-maa"),
            ("เรื่อยๆ", "rʉ̂ʉai-rʉ̂ʉai"),
            ("บ่อยๆ", "bɔ̀ɔi-bɔ̀ɔi"),
            ("ช้าๆ", "cháa-cháa"),
        ],
    )
    def test_mai_yamok_repetition(self, thai: str, expected: str) -> None:
        assert thai_to_pronunciation(thai) == expected

    def test_tltk_sentence_boundary_is_preserved_as_space(self) -> None:
        assert thai_to_pronunciation("กรุงเทพ สนุกมาก") == "krung-thêep sà-nùk-mâak"

    def test_empty_string(self) -> None:
        result = thai_to_pronunciation("")
        assert result == ""


class TestPosTagging:
    """品詞タグの日本語変換テスト"""

    @pytest.mark.parametrize(
        "word, expected_pos",
        [
            ("กิน", "動詞"),
            # ดี は形容詞辞書で確定させる。旧 perceptron は「副詞」を返していた
            ("ดี", "形容詞"),
            ("มาก", "副詞"),
            # ไม่ は否定詞。旧 perceptron は「助詞」を返していた
            ("ไม่", "否定詞"),
        ],
    )
    def test_pos_returns_japanese(self, word: str, expected_pos: str) -> None:
        result = get_pos_japanese(word)
        # POSタグは日本語であること（英語タグではない）
        assert result == expected_pos

    @pytest.mark.parametrize(
        "word, expected_pos",
        [
            # 機能語辞書で確定させる語。perceptron は未知語として
            # すべて「名詞」に誤判定していた
            ("ครับ", "助詞"),
            ("นะครับ", "助詞"),
            ("มึง", "代名詞"),
            ("อันนี้", "限定詞"),
            ("โอ้โห", "感嘆詞"),
            ("หน่อย", "副詞"),
        ],
    )
    def test_function_words_are_not_misjudged_as_noun(
        self, word: str, expected_pos: str
    ) -> None:
        assert get_pos_japanese(word) == expected_pos

    @pytest.mark.parametrize(
        "word",
        ["ดี", "สวย", "อร่อย", "แพง", "ใหญ่", "เร็ว", "หิว", "ดีใจ"],
    )
    def test_adjectives_are_unified(self, word: str) -> None:
        """タイ語の形容詞は状態動詞だがコーパスにより ADJ/VERB/ADV に割れるため、
        辞書で「形容詞」に統一する。"""
        assert get_pos_japanese(word) == "形容詞"

    @pytest.mark.parametrize("word", ["ชอบ", "กิน", "รู้"])
    def test_action_verbs_stay_verbs(self, word: str) -> None:
        """目的語を取る動詞は形容詞辞書に含めない。"""
        assert get_pos_japanese(word) == "動詞"
