from sentence_handlers import _build_sentence_data


def test_build_sentence_data_includes_key_word_pronunciation():
    sentence = {
        "thai_text": "ฉันกินข้าว",
        "pronunciation": "chǎn kin khâao",
        "japanese_translation": "私はご飯を食べます。",
        "word_breakdown": [
            {"word": "ฉัน", "pronunciation": "chǎn", "meaning": "私"},
            {"word": "กิน", "pronunciation": "kin", "meaning": "食べる"},
            {"word": "ข้าว", "pronunciation": "khâao", "meaning": "ご飯"},
        ],
    }

    sentence_data = _build_sentence_data(
        sentence,
        "ข้าว",
        use_premium_spec=False,
    )

    assert sentence_data["key_word"] == "ข้าว"
    assert sentence_data["key_word_pronunciation"] == "khâao"
    assert sentence_data["key_word_meaning"] == "ご飯"


def test_build_sentence_data_uses_empty_key_word_pronunciation_when_missing():
    sentence = {
        "thai_text": "ฉันกินข้าว",
        "pronunciation": "chǎn kin khâao",
        "japanese_translation": "私はご飯を食べます。",
        "word_breakdown": [
            {"word": "ฉัน", "pronunciation": "chǎn"},
            {"word": "กิน", "pronunciation": "kin"},
        ],
    }

    sentence_data = _build_sentence_data(
        sentence,
        "ข้าว",
        use_premium_spec=True,
    )

    assert sentence_data["key_word_pronunciation"] == ""
    assert sentence_data["key_word_meaning"] == ""
