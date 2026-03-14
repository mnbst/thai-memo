"""タイ語コーパスから頻出順位辞書を生成するスクリプト。

【目的】
タイ語テキストコーパス (corpus/th.txt) を PyThaiNLP で形態素解析し、
各単語の出現回数をカウントして頻出順位を付与する。
出力される freq_rank.json は UVM の新規単語選定の基盤データとなる。

【使い方】
    cd scripts
    python build_freq_rank.py
    # → freq_rank.json が生成される
    # その後 extract_top5000.py で上位10000語を抽出

【入力】
    corpus/th.txt — タイ語テキストコーパス（1行1文）

【出力】
    freq_rank.json — {word: rank} 形式。rank=1 が最頻出。
"""

from collections import Counter
from pythainlp.tokenize import word_tokenize
import json
import re

# タイ文字 (U+0E01〜U+0E5B) を1文字以上含む単語のみ許可。
# 数字・記号・英語のみのトークンを除外するためのフィルタ。
thai_re = re.compile(r"[\u0E01-\u0E5B]")

counter = Counter()

# コーパスを1行ずつ読み込み、PyThaiNLP で単語分割してカウント
with open("corpus/th.txt") as f:
    for i, line in enumerate(f):
        words = word_tokenize(line.strip())  # PyThaiNLP のデフォルト辞書で分割
        for w in words:
            w = w.strip()
            if not w or not thai_re.search(w):
                continue  # 空文字やタイ文字を含まないトークンをスキップ
            counter[w] += 1
        if (i + 1) % 500000 == 0:
            print(f"{i+1} lines processed...")

print(f"Total lines: {i+1}, unique words: {len(counter)}")

# 出現回数降順で並べ、1-indexed の順位を付与
freq = counter.most_common()

freq_rank = {}
for i, (word, count) in enumerate(freq):
    freq_rank[word] = i + 1  # rank=1 が最頻出

with open("freq_rank.json", "w") as f:
    json.dump(freq_rank, f, ensure_ascii=False)

print("freq_rank.json saved.")
print(f"Top 10: {freq[:10]}")
