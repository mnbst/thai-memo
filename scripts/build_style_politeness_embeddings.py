"""文体・丁寧さラベルの embedding を事前計算するビルドスクリプト。

【使い方】
    cd scripts
    python build_style_politeness_embeddings.py
    # → corpus/style_embeddings.json, corpus/politeness_embeddings.json が生成される
"""

import json
import sys
from pathlib import Path

from vertexai.language_models import TextEmbeddingModel

FUNCTIONS_DIR = Path(__file__).resolve().parents[1] / "functions" / "python"
sys.path.insert(0, str(FUNCTIONS_DIR))

from constants import POLITENESS_LEVELS, STYLES  # noqa: E402

STYLE_EMBEDDING_TEXTS = {
    STYLES[0]: "ニュース、報道、社会的な出来事、客観的な説明、仕事や公共の場面に合う文体",
    STYLES[1]: "友達、家族、日常会話、雑談、くだけた自然な話し言葉",
    STYLES[2]: "店員、先生、上司、初対面、依頼、礼儀が必要な場面に合う丁寧な文体",
    STYLES[3]: "SNS、チャット、短いメッセージ、親しい相手への軽い表現",
    STYLES[4]: "物語、文学、感情描写、情景描写、書き言葉らしい表現",
}

POLITENESS_EMBEDDING_TEXTS = {
    POLITENESS_LEVELS[0]: "目上の人、仕事、学校、寺院、初対面、依頼、礼儀正しい場面",
    POLITENESS_LEVELS[1]: "友達、家族、恋愛、趣味、SNS、親しい関係での自然な会話",
    POLITENESS_LEVELS[2]: "日常会話、買い物、交通、天気、一般的で偏りの少ない場面",
}

OUTPUT_STYLE = Path("corpus/style_embeddings.json")
OUTPUT_POLITENESS = Path("corpus/politeness_embeddings.json")
DIM = 768


def _write_embeddings(
    model,
    texts: dict[str, str],
    output: Path,
) -> None:
    labels = list(texts.keys())
    contents = [f"{label}: {texts[label]}" for label in labels]
    embeddings = model.get_embeddings(contents, output_dimensionality=DIM)  # type: ignore

    result = {}
    for label, emb in zip(labels, embeddings):
        result[label] = emb.values

    with open(output, "w", encoding="utf-8") as f:
        json.dump(result, f, ensure_ascii=False)

    print(f"Done: {len(result)} labels -> {output}")


def main():
    model = TextEmbeddingModel.from_pretrained("gemini-embedding-001")
    _write_embeddings(model, STYLE_EMBEDDING_TEXTS, OUTPUT_STYLE)
    _write_embeddings(model, POLITENESS_EMBEDDING_TEXTS, OUTPUT_POLITENESS)


if __name__ == "__main__":
    main()
