"""感情ラベルの embedding を事前計算するビルドスクリプト。

【使い方】
    cd scripts
    python build_emotion_embeddings.py
    # → corpus/emotion_embeddings.json が生成される
"""

import json
import sys
from pathlib import Path

from vertexai.language_models import TextEmbeddingModel

FUNCTIONS_DIR = Path(__file__).resolve().parents[1] / "functions" / "python"
sys.path.insert(0, str(FUNCTIONS_DIR))

from constants import EMOTIONS  # noqa: E402

OUTPUT = Path("corpus/emotion_embeddings.json")
DIM = 768


def main():
    model = TextEmbeddingModel.from_pretrained("gemini-embedding-001")
    embeddings = model.get_embeddings(EMOTIONS, output_dimensionality=DIM)  # type: ignore

    result = {}
    for emotion, emb in zip(EMOTIONS, embeddings):
        result[emotion] = emb.values

    with open(OUTPUT, "w", encoding="utf-8") as f:
        json.dump(result, f, ensure_ascii=False)

    print(f"Done: {len(result)} emotions -> {OUTPUT}")


if __name__ == "__main__":
    main()
