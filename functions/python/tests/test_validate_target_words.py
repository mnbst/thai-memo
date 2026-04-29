from sentence_service import validate_target_words


class TestValidateTargetWords:
    def test_none_target_words(self):
        assert validate_target_words({"thai_text": "สวัสดี"}, None) == []

    def test_empty_target_words(self):
        assert validate_target_words({"thai_text": "สวัสดี"}, []) == []

    def test_all_in_word_breakdown(self):
        sentence = {
            "thai_text": "ฉันกินข้าว",
            "word_breakdown": [
                {"word": "ฉัน", "meaning": "私"},
                {"word": "กิน", "meaning": "食べる"},
                {"word": "ข้าว", "meaning": "ご飯"},
            ],
        }
        assert validate_target_words(sentence, ["ฉัน", "กิน"]) == []

    def test_in_thai_text_but_not_breakdown_is_missing(self):
        sentence = {
            "thai_text": "ฉันกินข้าว",
            "word_breakdown": [
                {"word": "ฉัน", "meaning": "私"},
            ],
        }
        assert validate_target_words(sentence, ["กิน"]) == ["กิน"]

    def test_compound_only_is_missing(self):
        sentence = {
            "thai_text": "ใช่ไหมครับ",
            "word_breakdown": [
                {"word": "ใช่ไหม", "meaning": "そうですか"},
                {"word": "ครับ", "meaning": "丁寧語"},
            ],
        }
        assert validate_target_words(sentence, ["ใช่"]) == ["ใช่"]

    def test_reduplication_match(self):
        sentence = {
            "word_breakdown": [
                {"word": "เด็กๆ", "meaning": "子供たち"},
            ],
        }
        assert validate_target_words(sentence, ["เด็ก"]) == []

    def test_missing_words(self):
        sentence = {
            "thai_text": "สวัสดีครับ",
            "word_breakdown": [
                {"word": "สวัสดี", "meaning": "こんにちは"},
                {"word": "ครับ", "meaning": "丁寧語"},
            ],
        }
        missing = validate_target_words(sentence, ["ฉัน", "สวัสดี"])
        assert missing == ["ฉัน"]

    def test_empty_sentence(self):
        assert validate_target_words({}, ["กิน"]) == ["กิน"]

    def test_partial_match(self):
        sentence = {
            "thai_text": "ของานนี้เสร็จแล้วนะครับ",
            "word_breakdown": [
                {"word": "ขอ", "meaning": "お願いする"},
                {"word": "งาน", "meaning": "仕事"},
                {"word": "นี้", "meaning": "この"},
            ],
        }
        missing = validate_target_words(sentence, ["ของ", "งาน"])
        assert missing == ["ของ"]
