"""freq_rank_top10000.json からタイ語単語の embedding を生成するビルドスクリプト。

【目的】
UVM のセマンティック重複除去 (embeddings.py) で使用する
embedding データを事前計算し、ローカルに保存する。
生成後は GCS にアップロードして Cloud Functions から参照する。

【使い方】
    cd scripts
    python build_embeddings.py
    # → corpus/vocab_embeddings.npy, corpus/vocab_words.json が生成される
    # その後 upload_corpus.sh で GCS にアップロード

【出力ファイル】
    corpus/vocab_embeddings.npy  — (10000, 768) float32 の numpy 配列
                                   i 行目が vocab_words.json の i 番目の単語に対応
    corpus/vocab_words.json      — [{"word": "ฉัน", "rank": 1}, ...]
                                   npy の行インデックスとの対応を保持

【注意事項】
    - Vertex AI の認証設定 (gcloud auth) が必要
    - API レート制限回避のため BATCH_SIZE 件ごとに SLEEP 秒待機
    - 全10000語の処理に数分かかる
"""

import json
import time
from pathlib import Path

import numpy as np
from vertexai.language_models import TextEmbeddingModel

INPUT = Path("corpus/freq_rank_top10000.json")  # 入力: 頻出順位付き語彙リスト
OUTPUT_NPY = Path("corpus/vocab_embeddings.npy")  # 出力: embedding 行列
OUTPUT_WORDS = Path("corpus/vocab_words.json")     # 出力: 単語メタデータ
BATCH_SIZE = 250  # 1回の API 呼び出しで処理する単語数
SLEEP = 1         # バッチ間の待機時間（秒）— レート制限回避
DIM = 768         # embedding の次元数（gemini-embedding-001 の出力次元）


def main():
    # Gemini Embedding モデルを読み込み
    model = TextEmbeddingModel.from_pretrained("gemini-embedding-001")

    # 頻出順位辞書を読み込み（{word: rank} 形式）
    with open(INPUT) as f:
        freq_rank: dict[str, int] = json.load(f)

    words = list(freq_rank.keys())
    # 全単語分の embedding を格納する配列を事前確保
    all_embs = np.empty((len(words), DIM), dtype=np.float32)

    # バッチ単位で Vertex AI API を呼び出し
    for i in range(0, len(words), BATCH_SIZE):
        batch = words[i : i + BATCH_SIZE]
        embeddings = model.get_embeddings(batch, output_dimensionality=DIM)
        for j, emb in enumerate(embeddings):
            all_embs[i + j] = emb.values  # API レスポンスから float 配列を取得
        done = min(i + BATCH_SIZE, len(words))
        print(f"{done}/{len(words)}")
        if done < len(words):
            time.sleep(SLEEP)  # レート制限回避

    # numpy バイナリ形式で保存（GCS にアップロード後、CF が np.load で読む）
    np.save(OUTPUT_NPY, all_embs)

    # 単語メタデータを JSON で保存（行番号 ↔ 単語の対応表）
    word_meta = [{"word": w, "rank": freq_rank[w]} for w in words]
    with open(OUTPUT_WORDS, "w", encoding="utf-8") as f:
        json.dump(word_meta, f, ensure_ascii=False)

    print(f"Done: {all_embs.shape} -> {OUTPUT_NPY}")


if __name__ == "__main__":
    main()
