"""word_breakdown の欠落検出と補完のテスト。"""

from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from word_gap import apply_gap_words, build_gap_prompt, find_gaps


def _sentence(thai: str, words: list[str]) -> dict:
    return {
        "thai_text": thai,
        "word_breakdown": [{"word": w, "meaning": "x"} for w in words],
    }


def test_no_gap_when_breakdown_covers_text() -> None:
    s = _sentence("ทางปิดหรอ งั้นไปทางไหนดี",
                  ["ทาง", "ปิด", "หรอ", "งั้น", "ไป", "ทาง", "ไหน", "ดี"])
    assert find_gaps(s) == []


def test_detects_missing_word_in_middle() -> None:
    # 2つ目の ทาง が欠落しているケース（実測された失敗）
    s = _sentence("ทางปิดหรอ งั้นไปทางไหนดี",
                  ["ทาง", "ปิด", "หรอ", "งั้น", "ไป", "ไหน", "ดี"])
    assert find_gaps(s) == [(5, "ทาง")]


def test_detects_missing_word_at_end() -> None:
    s = _sentence("เสื้อตัวนี้ถูกจัง ซื้อได้เลย",
                  ["เสื้อ", "ตัว", "นี้", "ถูก", "จัง", "ซื้อ", "ได้"])
    assert find_gaps(s) == [(7, "เลย")]


def test_word_not_in_text_is_unrepairable() -> None:
    s = _sentence("วัดนี้สวย", ["วัด", "นี้", "ใหญ่"])
    assert find_gaps(s) == [(-1, "")]


def test_apply_gap_words_inserts_at_position() -> None:
    s = _sentence("ทางปิดหรอ งั้นไปทางไหนดี",
                  ["ทาง", "ปิด", "หรอ", "งั้น", "ไป", "ไหน", "ดี"])
    gaps = find_gaps(s)

    assert apply_gap_words(s, gaps, [{"word": "ทาง", "meaning": "道"}])

    assert [w["word"] for w in s["word_breakdown"]] == [
        "ทาง", "ปิด", "หรอ", "งั้น", "ไป", "ทาง", "ไหน", "ดี",
    ]
    assert s["word_breakdown"][5]["meaning"] == "道"


def test_apply_gap_words_splits_multi_word_segment() -> None:
    s = _sentence("ไปวัดนี้ได้ไหม", ["ไป", "วัด", "ได้", "ไหม"])
    gaps = find_gaps(s)

    assert apply_gap_words(
        s, gaps, [{"word": "นี้", "meaning": "この"}]
    )
    assert [w["word"] for w in s["word_breakdown"]] == [
        "ไป", "วัด", "นี้", "ได้", "ไหม",
    ]


def test_apply_gap_words_rejects_mismatched_fill() -> None:
    s = _sentence("ทางปิดหรอ งั้นไปทางไหนดี",
                  ["ทาง", "ปิด", "หรอ", "งั้น", "ไป", "ไหน", "ดี"])
    gaps = find_gaps(s)

    assert not apply_gap_words(s, gaps, [{"word": "โรงแรม", "meaning": "ホテル"}])


def test_gap_prompt_contains_text_and_segments() -> None:
    prompt = build_gap_prompt("ทางปิดหรอ", [(5, "ทาง")])
    assert "ทางปิดหรอ" in prompt and "ทาง" in prompt


def test_pronunciation_fallback_keeps_word_spacing() -> None:
    """フォールバックでも語ごとスペース区切りの表記を保つ。"""
    from word_gap import repair_pronunciation

    s = {"thai_text": "ไม่ทีที่ไหนขายสีนี้เลย"}
    repair_pronunciation(s)

    # 全音節がハイフンで繋がる形（一括変換）になっていないこと
    assert " " in s["pronunciation"]
    assert s["pronunciation"].split(" ")[0] == "mâi"
