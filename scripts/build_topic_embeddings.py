"""テーマ・サブテーマの embedding を事前計算するビルドスクリプト。

【使い方】
    cd scripts
    python build_topic_embeddings.py
    # → corpus/topic_embeddings.json, corpus/sub_theme_embeddings.json が生成される

生成後は upload_corpus.sh で GCS にアップロードする。
"""

import io
import json
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "functions" / "python"))
from constants import TOPICS, TOPIC_SUB_THEMES  # noqa: E402
from themes.bl_drama import BL_DRAMA_SHOTS  # noqa: E402

from vertexai.language_models import TextEmbeddingModel  # noqa: E402

TOPIC_OUTPUT = Path("corpus/topic_embeddings.json")
SUB_THEME_OUTPUT = Path("corpus/sub_theme_embeddings.json")
SHOT_OUTPUT = Path("corpus/shot_embeddings.json")
DIM = 768

BL_DRAMA_TOPIC = "タイBLドラマ（告白、すれ違い、再会、嫉妬、裏切り、仲直り、壁ドン、あだ名呼び）"


def _build_bl_drama_centroid(
    model: TextEmbeddingModel,
    vocab_emb_path: Path,
    vocab_words_path: Path,
) -> list[float]:
    """BLドラマショットに含まれるタイ語単語のembedding平均を計算する。

    vocab_embeddings から取得できる単語のみ使用。
    取得できない場合はショット文全体のembeddingにフォールバック。
    """
    emb_matrix = np.load(str(vocab_emb_path), allow_pickle=False)
    with open(vocab_words_path, encoding="utf-8") as f:
        vocab_words = json.load(f)
    word_to_idx = {entry["word"]: i for i, entry in enumerate(vocab_words)}

    # ショット文に含まれるvocab単語を検出（タイ語はスペース区切りできないため部分文字列マッチ）
    # 最頻出の機能語（rank上位100）は除外し、内容語のみでcentroidを構成する
    MIN_RANK = 100
    all_shot_text = " ".join(BL_DRAMA_SHOTS.values())

    matched_embs: list[np.ndarray] = []
    matched_words: list[str] = []
    for entry in vocab_words:
        word = entry["word"]
        rank = entry.get("rank", 0)
        idx = word_to_idx.get(word)
        if idx is None or len(word) < 2 or rank < MIN_RANK:
            continue
        if word in all_shot_text:
            matched_embs.append(emb_matrix[idx])
            matched_words.append(word)

    print(f"BL drama centroid: {len(matched_embs)} vocab words found in shots")
    if matched_words:
        print(f"  sample words: {matched_words[:20]}")

    if matched_embs:
        centroid = np.mean(np.stack(matched_embs), axis=0)
        return centroid.tolist()

    # フォールバック: ショット文全体のembeddingの平均
    shot_texts = list(BL_DRAMA_SHOTS.values())
    shot_embs = model.get_embeddings(shot_texts, output_dimensionality=DIM)  # type: ignore
    vectors = [np.array(e.values, dtype=np.float32) for e in shot_embs]
    centroid = np.mean(np.stack(vectors), axis=0)
    print("BL drama centroid: using sentence-level fallback")
    return centroid.tolist()


def main():
    model = TextEmbeddingModel.from_pretrained("gemini-embedding-001")

    # --- テーマ embedding ---
    embeddings = model.get_embeddings(TOPICS, output_dimensionality=DIM)  # type: ignore
    topic_result = {}
    for topic, emb in zip(TOPICS, embeddings):
        topic_result[topic] = emb.values

    # BLドラマはテキストベースembeddingをそのまま使用
    # centroidだと機能語が上位に来てテーマ弁別力が弱いため

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

    # --- BLドラマ 参考セリフ embedding ---
    # キーはショットIDではなくタイ語本文。本文を書き換えた行は embedding が
    # 引けなくなり選出候補から外れるため、更新漏れが誤スコアではなく
    # スキップとして現れる。
    all_shots: list[str] = []
    for text in BL_DRAMA_SHOTS.values():
        if text not in all_shots:
            all_shots.append(text)

    shot_embeddings = model.get_embeddings(all_shots, output_dimensionality=DIM)  # type: ignore
    shot_result = {}
    for label, emb in zip(all_shots, shot_embeddings):
        shot_result[label] = emb.values

    with open(SHOT_OUTPUT, "w", encoding="utf-8") as f:
        json.dump(shot_result, f, ensure_ascii=False)
    print(f"Shots: {len(shot_result)} -> {SHOT_OUTPUT}")


if __name__ == "__main__":
    main()
