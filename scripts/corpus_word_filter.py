"""Common word quality filters for Thai corpus frequency lists."""

from __future__ import annotations

import re

from pythainlp.corpus.common import thai_stopwords, thai_words

# POS tags that mostly represent noise for vocabulary ranking.
DROP_TAGS = {"INTJ", "PUNCT"}

# Keep a PyThaiNLP dictionary gate to remove mojibake and broken tokenizer
# fragments while still allowing known Thai words and common loanwords.
THAI_WORDS = thai_words()

# PyThaiNLP's dictionary intentionally contains some particles and
# interjections, so keep an explicit denylist for learning-vocabulary output.
DENYLIST = {
    "ๆ",
    "ฯ",
    "ฯลฯ",
    "ครับ",
    "ค่ะ",
    "คะ",
    "นะ",
    "น่ะ",
    "นะคะ",
    "นะครับ",
    "ล่ะ",
    "หล่ะ",
    "ละ",
    "สิ",
    "ซิ",
    "เถอะ",
    "หรอก",
    "แหละ",
    "ไง",
    "เนี่ย",
    "จัง",
    "หน่อย",
    "วะ",
    "อะ",
    "อ่ะ",
    "อ่า",
    "อา",
    "เอ่อ",
    "เออ",
    "อืม",
    "อึม",
    "อ้อ",
    "โอ",
    "โอ้",
    "โอ๊ย",
    "โอ๊ว",
    "โว้ว",
    "ว้าว",
    "เฮ้",
    "เฮ้ย",
    "เฮ",
    "ฮะ",
    "ฮา",
    "ฮิ",
    "อ้าว",
    "เอ๊ะ",
    "อ๊ะ",
    "ฮึ",
    "เห",
    "เหรอ",
    "หรอ",
    "มั้ย",
    "มั๊ย",
    "ไหม",
    "จ้ะ",
    "จ๊ะ",
    "จ้า",
    "ปัดโธ่",
}
DENYLIST |= thai_stopwords() & {
    "ครับ",
    "ค่ะ",
    "คะ",
    "นะ",
    "มั้ย",
    "ไหม",
    "จ้ะ",
    "จ๊ะ",
}

THAI_RE = re.compile(r"[\u0E01-\u0E5B]")
THAI_ONLY_RE = re.compile(r"^[\u0E01-\u0E3A\u0E40-\u0E4E]+(?: ๆ)?$")

# Common UTF-8/TIS-620 mojibake fragments in the source corpus.
MOJIBAKE_RE = re.compile(r"(?:เธ[ก-ฮะ-ู็-์]|เน[ก-ฮะ-ู็-์])")


def should_keep_word(word: str, tag: str | None = None) -> bool:
    word = word.strip()
    if not word or not THAI_RE.search(word):
        return False
    if tag in DROP_TAGS:
        return False
    if word in DENYLIST:
        return False
    if MOJIBAKE_RE.search(word):
        return False
    if not THAI_ONLY_RE.fullmatch(word):
        return False
    if word not in THAI_WORDS:
        return False
    return True
