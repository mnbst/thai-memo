"""thai_text へ漏れた分かち書きの詰め直し（_normalize_thai_spacing）。"""

import pytest

from sentence_service import _normalize_thai_spacing


def _sentence(thai: str, words: list[str]) -> dict:
    return {
        "thai_text": thai,
        "word_breakdown": [{"word": w, "meaning": ""} for w in words],
    }


# 2026-08-06 に生成 548 文から実際に拾った分かち書き崩壊
@pytest.mark.parametrize(
    ("thai", "words", "expected"),
    [
        (
            "พี่ชาย ฉัน เพิ่ง รู้จัก เธอ",
            ["พี่ชาย", "ฉัน", "เพิ่ง", "รู้จัก", "เธอ"],
            "พี่ชายฉันเพิ่งรู้จักเธอ",
        ),
        (
            "แก ลืม พาสปอร์ต ไว้ ที่ สนามบิน",
            ["แก", "ลืม", "พาสปอร์ต", "ไว้", "ที่", "สนามบิน"],
            "แกลืมพาสปอร์ตไว้ที่สนามบิน",
        ),
        (
            "คุณใส่ น้ำตาล ใน กาแฟ ไหม ครับ",
            ["คุณ", "ใส่", "น้ำตาล", "ใน", "กาแฟ", "ไหม", "ครับ"],
            "คุณใส่น้ำตาลในกาแฟไหมครับ",
        ),
        (
            "มีสิ่ง ที่ ต้อง ดู ระหว่างทาง ครับ",
            ["มี", "สิ่ง", "ที่", "ต้อง", "ดู", "ระหว่างทาง", "ครับ"],
            "มีสิ่งที่ต้องดูระหว่างทางครับ",
        ),
        (
            "ทัวร์นี้ น่าจะ เริ่ม แล้ว",
            ["ทัวร์", "นี้", "น่าจะ", "เริ่ม", "แล้ว"],
            "ทัวร์นี้น่าจะเริ่มแล้ว",
        ),
    ],
)
def test_collapsed_sentences_are_joined(thai, words, expected):
    s = _sentence(thai, words)
    _normalize_thai_spacing(s)
    assert s["thai_text"] == expected


def test_two_clause_sentence_keeps_its_space():
    s = _sentence("ฝนตก ไปดูวัดไม่ได้", ["ฝน", "ตก", "ไป", "ดู", "วัด", "ไม่ได้"])
    _normalize_thai_spacing(s)
    assert s["thai_text"] == "ฝนตก ไปดูวัดไม่ได้"


def test_space_before_yamok_is_closed_for_tts():
    """正式記法は ๆ の前を空けるが、TTS が分断して読むので詰める。"""
    s = _sentence("น้องน่ารักจริง ๆ ค่ะ", ["น้อง", "น่ารัก", "จริง ๆ", "ค่ะ"])
    _normalize_thai_spacing(s)
    assert s["thai_text"] == "น้องน่ารักจริงๆ ค่ะ"
    assert [wb["word"] for wb in s["word_breakdown"]] == [
        "น้อง",
        "น่ารัก",
        "จริงๆ",
        "ค่ะ",
    ]


def test_space_after_yamok_is_kept_as_a_possible_clause_break():
    s = _sentence("รีบ ๆ หน่อย เดี๋ยวไม่ทัน", ["รีบ ๆ", "หน่อย", "เดี๋ยว", "ไม่ทัน"])
    _normalize_thai_spacing(s)
    assert s["thai_text"] == "รีบๆ หน่อย เดี๋ยวไม่ทัน"


def test_partially_split_sentence_is_left_alone():
    """空白過多だが語ごとには割れていない文。節の切れ目を壊さない。"""
    thai = "หลงแล้ว แก รู้ทางไปสถานีไหม"
    s = _sentence(thai, ["หลง", "แล้ว", "แก", "รู้", "ทางไป", "สถานี", "ไหม"])
    _normalize_thai_spacing(s)
    assert s["thai_text"] == thai


def test_untouched_when_breakdown_does_not_cover_the_sentence():
    """語が欠けている文は判定できないので触らない（欠落補完側の担当）。"""
    thai = "แก ลืม พาสปอร์ต ไว้ ที่ สนามบิน"
    s = _sentence(thai, ["แก", "ลืม", "พาสปอร์ต"])
    _normalize_thai_spacing(s)
    assert s["thai_text"] == thai
