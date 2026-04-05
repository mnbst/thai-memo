"""freq_rank.json から上位10000語を抽出するスクリプト。

【目的】
build_freq_rank.py で生成した全語彙の freq_rank.json から
上位10000語のみを抽出する。このファイルは以下の用途で使用される:
  - build_embeddings.py の入力（embedding 生成対象）
  - Flutter アプリの assets/（AssessmentScreen での語彙評価）
  - Cloud Functions での新規単語候補選定

【使い方】
    cd scripts
    python extract_top5000.py
    # → corpus/freq_rank_top10000.json が生成される
"""

import json
from pathlib import Path

INPUT = Path("corpus/freq_rank.json")
OUTPUT = Path("corpus/freq_rank_top10000.json")

with INPUT.open(encoding="utf-8") as f:
    freq_rank = json.load(f)

# rank <= 10000 の単語のみ抽出
top10000 = {w: rank for w, rank in freq_rank.items() if rank <= 10000}

with OUTPUT.open("w", encoding="utf-8") as f:
    json.dump(top10000, f, ensure_ascii=False)

print(f"{OUTPUT} saved. {len(top10000)} words.")
