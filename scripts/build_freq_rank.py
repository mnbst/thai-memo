"""タイ語コーパスから頻出順位辞書を生成するスクリプト。

【目的】
タイ語テキストコーパス (corpus/th.txt) を PyThaiNLP で形態素解析し、
各単語の出現回数をカウントして頻出順位を付与する。
会話的な感嘆詞・終助詞・記号類は、品詞タグと denylist で除外する。

【使い方】
    cd scripts
    python build_freq_rank.py
    # → corpus/freq_rank.json が生成される
    # その後 extract_top5000.py で上位10000語を抽出

【入力】
    corpus/th.txt — タイ語テキストコーパス（1行1文）

【出力】
    corpus/freq_rank.json — {word: rank} 形式。rank=1 が最頻出。
"""

from collections import Counter
import json
from pathlib import Path
import re

from pythainlp.corpus.common import thai_stopwords
from pythainlp.tag import pos_tag
from pythainlp.tokenize import word_tokenize

INPUT = Path("corpus/th.txt")
OUTPUT = Path("corpus/freq_rank.json")
# `PART` は `ไม่` のような重要語も含むため、会話粒子は denylist で個別に落とす。
DROP_TAGS = {"INTJ", "PUNCT"}

# 文脈付きPOSでも取りこぼしやすい会話粒子・感嘆詞を補助的に除外する。
DENYLIST = {
    "ๆ",
    "ฯ",
    "ฯลฯ",
    "ครับ",
    "ค่ะ",
    "คะ",
    "นะ",
    "ล่ะ",
    "ละ",
    "สิ",
    "เหรอ",
    "หรอ",
    "มั้ย",
    "ไหม",
    "จ้ะ",
    "จ๊ะ",
    "จ้า",
    "ฮะ",
    "โอ๊ย",
    "อ้าว",
    "เฮ้ย",
    "เอ๊ะ",
    "อ๊ะ",
    "ฮึ",
    "เออ",
    "อืม",
}
DENYLIST |= thai_stopwords() & {"ครับ", "ค่ะ", "คะ", "นะ", "มั้ย", "ไหม", "จ้ะ", "จ๊ะ"}

# 数字・記号・英語のみのトークンを避けるため、タイ文字を1字以上含む語のみ残す。
THAI_RE = re.compile(r"[\u0E01-\u0E5B]")


def should_keep_word(word: str, tag: str) -> bool:
    if not word or not THAI_RE.search(word):
        return False
    # 単一文字はトークナイザーの分割ミスまたは略語のため除外
    if len(word) < 2:
        return False
    if word in DENYLIST:
        return False
    if tag in DROP_TAGS:
        return False
    return True


def main() -> None:
    counter: Counter[str] = Counter()
    total_lines = 0

    with INPUT.open(encoding="utf-8") as f:
        for total_lines, line in enumerate(f, start=1):
            words = [
                word.strip()
                for word in word_tokenize(line.strip(), keep_whitespace=False)
            ]
            words = [word for word in words if word]
            if not words:
                continue

            for word, tag in pos_tag(words, engine="perceptron", corpus="orchid_ud"):
                if should_keep_word(word, tag):
                    counter[word] += 1

            if total_lines % 500000 == 0:
                print(f"{total_lines} lines processed...")

    print(f"Total lines: {total_lines}, unique words: {len(counter)}")

    freq = counter.most_common()
    freq_rank = {word: i + 1 for i, (word, _) in enumerate(freq)}

    with OUTPUT.open("w", encoding="utf-8") as f:
        json.dump(freq_rank, f, ensure_ascii=False)

    print(f"{OUTPUT} saved.")
    print(f"Top 10: {freq[:10]}")


if __name__ == "__main__":
    main()
