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

import json
from pathlib import Path
from collections import Counter

from pythainlp.tag import pos_tag
from pythainlp.tokenize import word_tokenize

from corpus_word_filter import should_keep_word

SCRIPT_DIR = Path(__file__).resolve().parent
INPUT = SCRIPT_DIR / "corpus/th.txt"
OUTPUT = SCRIPT_DIR / "corpus/freq_rank.json"
TOP_OUTPUT = SCRIPT_DIR / "corpus/freq_rank_top10000.json"
TOP_LIMIT = 10000


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
    top10000 = {word: i + 1 for i, (word, _) in enumerate(freq[:TOP_LIMIT])}

    with OUTPUT.open("w", encoding="utf-8") as f:
        json.dump(freq_rank, f, ensure_ascii=False)
    with TOP_OUTPUT.open("w", encoding="utf-8") as f:
        json.dump(top10000, f, ensure_ascii=False)

    print(f"{OUTPUT} saved.")
    print(f"{TOP_OUTPUT} saved. {len(top10000)} words.")
    print(f"Top 10: {freq[:10]}")


if __name__ == "__main__":
    main()
