"""トピック文字列の embedding を事前計算するビルドスクリプト。

【目的】
UVM 単語選定時にトピックと語彙の類似度を計算するための
トピック embedding を事前生成し、ローカルに保存する。
生成後は upload_corpus.sh で GCS にアップロードする。

【使い方】
    cd scripts
    python build_topic_embeddings.py
    # → corpus/topic_embeddings.json が生成される

【出力ファイル】
    corpus/topic_embeddings.json — {"トピック文字列": [float, ...], ...}
"""

import json
from pathlib import Path

from vertexai.language_models import TextEmbeddingModel

OUTPUT = Path("corpus/topic_embeddings.json")
DIM = 768

# constants.py の TOPICS と同一（変更時は両方更新すること）
TOPICS = [
    "あいさつ（朝、昼、夜のあいさつ、初対面、久しぶりの再会など）",
    "食べ物（レストランでの注文、料理の感想、食材の購入など）",
    "旅行（ホテル予約、道案内、観光地での会話など）",
    "感情（喜び、悲しみ、驚き、不安などの表現）",
    "仕事（職場での会話、ビジネスマナー、打ち合わせなど）",
    "家族（家族の紹介、日常会話、家族行事など）",
    "買い物（値段交渉、商品の質問、支払いなど）",
    "交通（タクシー、電車、バスでの会話）",
    "健康（病院、薬局、体調不良の説明など）",
    "天気（天気の話題、季節の挨拶など）",
    "趣味（スポーツ、音楽、映画などの趣味について）",
    "学校（授業、宿題、学校生活について）",
    "宗教・信仰（寺院訪問、お参り、托鉢、僧侶との会話、仏教行事など）",
    "伝統・祭り（ソンクラーン、ロイクラトン、王室行事、伝統儀式など）",
    "礼儀作法（ワイ（合掌）、年長者への敬意、タブー、社会的マナーなど）",
    "恋愛・男女関係（告白、デート、口説き文句、恋人同士の会話、別れなど）",
]


def main():
    model = TextEmbeddingModel.from_pretrained("gemini-embedding-001")

    embeddings = model.get_embeddings(TOPICS, output_dimensionality=DIM)  # type: ignore

    result = {}
    for topic, emb in zip(TOPICS, embeddings):
        result[topic] = emb.values

    with open(OUTPUT, "w", encoding="utf-8") as f:
        json.dump(result, f, ensure_ascii=False)

    print(f"Done: {len(result)} topics -> {OUTPUT}")


if __name__ == "__main__":
    main()
