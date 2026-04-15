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

# functions/python/constants.py の TOPICS と同一（変更時は両方更新すること）
TOPICS = [
    "あいさつ（朝・昼・夜、初対面、再会、別れ、電話）",
    "食べ物（注文、感想、屋台、辛さ調整、アレルギー）",
    "旅行（ホテル、道案内、観光地、空港、ツアー）",
    "感情（喜び、悲しみ、驚き、不安、怒り、照れ）",
    "仕事（報告・連絡・相談、打ち合わせ、残業申請、同僚雑談）",
    "家族（家族紹介、子育て、親への感謝、兄弟、家族行事）",
    "買い物（値段交渉、サイズ・色の確認、返品、ナイトマーケット）",
    "交通（Grab、BTS、バイタク、ソンテウ、渋滞）",
    "健康（症状説明、薬局、マッサージ、健康診断）",
    "天気（暑さ、雨季、台風、日焼け対策）",
    "趣味（ムエタイ、音楽、映画、ゴルフ、SNS、ゲーム）",
    "学校（授業中、宿題、試験、放課後、語学学校）",
    "宗教・信仰（寺院マナー、托鉢、お守り、僧侶への話し方、仏教行事）",
    "伝統・祭り（ソンクラーン、ロイクラトン、王室行事、地域の伝統料理）",
    "礼儀作法（ワイの使い分け、敬語、タブー、食事マナー、贈り物）",
    "恋愛・男女関係（告白、デート、甘い言葉、遠距離、別れ、仲直り）",
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
