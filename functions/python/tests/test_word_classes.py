from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from prompts import build_word_class_constraint  # noqa: E402
from word_classes import CLASSES, classify, classify_all, is_function_word  # noqa: E402


def test_every_class_has_label_and_words() -> None:
    assert CLASSES
    for cid, c in CLASSES.items():
        assert c["label"], cid
        assert c["words"], cid
        assert isinstance(c.get("rule", ""), str), cid


def test_word_belongs_to_one_class_only() -> None:
    seen: dict[str, str] = {}
    for cid, c in CLASSES.items():
        for w in c["words"]:
            assert w not in seen, f"{w} が {seen.get(w)} と {cid} に重複"
            seen[w] = cid


def test_classify_known_and_unknown_words() -> None:
    assert classify("มัน") == "third_person"
    assert classify("อย่างนั้น") == "determiner"
    assert classify("หนึ่ง") == "numeral"
    assert classify("ทะเล") is None
    assert is_function_word("ด้วย")
    assert not is_function_word("ทะเล")


def test_words_that_can_head_a_sentence_are_not_function_words() -> None:
    """主語・主動詞になれる語に共通手順を付けると逆効果になる（実測済み）。"""
    for word in ["ผม", "ฉัน", "คุณ", "นี่", "นั่น", "ให้", "ได้", "อยู่", "คือ"]:
        assert not is_function_word(word), word


def test_classify_all_dedupes_and_keeps_order() -> None:
    assert classify_all(["มัน", "ทะเล", "เขา", "นี่"]) == [
        "third_person",
        "demonstrative_pronoun",
    ]
    assert classify_all(["ทะเล"]) == []
    assert classify_all(None) == []


def test_constraint_block_only_for_classified_words() -> None:
    block = build_word_class_constraint(["มัน"])
    assert "【ターゲット語は三人称代名詞】" in block
    # 機能語クラスには共通手順が付く
    assert "文の主役にならない" in block
    assert CLASSES["third_person"]["rule"] in block
    assert build_word_class_constraint(["ทะเล"]) == ""


def test_non_function_class_gets_rule_without_steps() -> None:
    block = build_word_class_constraint(["ผม"])
    assert "【ターゲット語は一・二人称代名詞】" in block
    assert "文の主役にならない" not in block
    assert CLASSES["personal_pronoun"]["rule"] in block


def test_constraint_block_merges_multiple_classes() -> None:
    block = build_word_class_constraint(["มัน", "หนึ่ง"])
    assert "【ターゲット語は三人称代名詞・数詞】" in block
    assert block.count("文の主役にならない") == 1
