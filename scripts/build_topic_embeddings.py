"""テーマ・サブテーマの embedding を事前計算するビルドスクリプト。

【使い方】
    cd scripts
    python build_topic_embeddings.py
    # → corpus/topic_embeddings.json, corpus/sub_theme_embeddings.json が生成される

生成後は upload_corpus.sh で GCS にアップロードする。
"""

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "functions" / "python"))
from constants import BL_DRAMA_SETTINGS, TOPICS, TOPIC_SUB_THEMES  # noqa: E402

from vertexai.language_models import TextEmbeddingModel  # noqa: E402

TOPIC_OUTPUT = Path("corpus/topic_embeddings.json")
SUB_THEME_OUTPUT = Path("corpus/sub_theme_embeddings.json")
SCENE_OUTPUT = Path("corpus/scene_embeddings.json")
DIM = 768


def main():
    model = TextEmbeddingModel.from_pretrained("gemini-embedding-001")

    # --- テーマ embedding ---
    embeddings = model.get_embeddings(TOPICS, output_dimensionality=DIM)  # type: ignore
    topic_result = {}
    for topic, emb in zip(TOPICS, embeddings):
        topic_result[topic] = emb.values

    with open(TOPIC_OUTPUT, "w", encoding="utf-8") as f:
        json.dump(topic_result, f, ensure_ascii=False)
    print(f"Topics: {len(topic_result)} -> {TOPIC_OUTPUT}")

    # --- サブテーマ embedding ---
    all_subs: list[str] = []
    for subs in TOPIC_SUB_THEMES.values():
        for s in subs:
            if s not in all_subs:
                all_subs.append(s)

    sub_embeddings = model.get_embeddings(all_subs, output_dimensionality=DIM)  # type: ignore
    sub_result = {}
    for label, emb in zip(all_subs, sub_embeddings):
        sub_result[label] = emb.values

    with open(SUB_THEME_OUTPUT, "w", encoding="utf-8") as f:
        json.dump(sub_result, f, ensure_ascii=False)
    print(f"Sub-themes: {len(sub_result)} -> {SUB_THEME_OUTPUT}")

    # --- BLドラマ シーン embedding ---
    all_scenes: list[str] = []
    for setting in BL_DRAMA_SETTINGS:
        for s in setting["scenes"]:
            if s not in all_scenes:
                all_scenes.append(s)

    scene_embeddings = model.get_embeddings(all_scenes, output_dimensionality=DIM)  # type: ignore
    scene_result = {}
    for label, emb in zip(all_scenes, scene_embeddings):
        scene_result[label] = emb.values

    with open(SCENE_OUTPUT, "w", encoding="utf-8") as f:
        json.dump(scene_result, f, ensure_ascii=False)
    print(f"Scenes: {len(scene_result)} -> {SCENE_OUTPUT}")


if __name__ == "__main__":
    main()
