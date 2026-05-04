"""Free tier 向け例文バッチ生成スクリプト。

freq_rank 上位115語 × 2文 = ~230文を事前生成し、
クライアントに同梱する JSON ファイルを出力する。

使い方:
  cd functions/python
  GCLOUD_PROJECT=thai-memo-prod python scripts/generate_free_sentences.py

出力:
  scripts/output/free_sentences.json
"""

import json
import os
import sys
import time

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

import random

from constants import FREE_STYLES, FREE_TOPICS, RESPONSE_JSON_SCHEMA, TOPICS
from llm_providers import generate_sentence_sync
from nlp import enrich_with_nlp
from prompts import SYSTEM_PROMPT_FREE, build_uvm_prompt, gate_topics_for_vocab
from sentence_service import validate_target_words

BL_DRAMA_TOPIC = TOPICS[15]
BL_DRAMA_RATIO = 0.35

SENTENCES_PER_WORD = 2
MAX_FREQ_RANK = 115
OUTPUT_DIR = os.path.join(os.path.dirname(__file__), "output")
OUTPUT_FILE = os.path.join(OUTPUT_DIR, "free_sentences.json")
PROGRESS_FILE = os.path.join(OUTPUT_DIR, "progress.json")
MAX_RETRY = 2


def load_freq_rank() -> dict[str, int]:
    from google.cloud import storage as gcs

    project_id = os.environ.get("GCLOUD_PROJECT", "")
    if not project_id:
        raise RuntimeError("GCLOUD_PROJECT 環境変数を設定してください")
    bucket_name = f"{project_id}-uvm-data"
    client = gcs.Client()
    blob = client.bucket(bucket_name).blob("freq_rank_top10000.json")
    return json.loads(blob.download_as_text())


def get_target_words(freq_rank: dict[str, int]) -> list[str]:
    sorted_words = sorted(freq_rank.items(), key=lambda x: x[1])
    return [word for word, rank in sorted_words if rank < MAX_FREQ_RANK]


def generate_one(
    word: str,
    estimated_vocab: int,
    sentence_index: int,
) -> dict:
    if random.random() < BL_DRAMA_RATIO:
        topic = BL_DRAMA_TOPIC
    else:
        topic_candidates = gate_topics_for_vocab(FREE_TOPICS, estimated_vocab)
        topic = random.choice(topic_candidates)

    params = {"topic": topic}
    target_words = [word]
    prompt = build_uvm_prompt(
        params,
        target_words,
        estimated_vocab=estimated_vocab,
        is_premium=False,
    )
    system_prompt = SYSTEM_PROMPT_FREE

    current_prompt = prompt
    for attempt in range(1 + MAX_RETRY):
        sentence = generate_sentence_sync(
            system_prompt, current_prompt, False, "free"
        )
        enrich_with_nlp(sentence)

        missing = validate_target_words(sentence, target_words)
        if not missing:
            return sentence

        print(f"  Retry {attempt + 1}: missing={missing}")
        missing_str = ", ".join(missing)
        current_prompt = (
            f"{prompt}\n\n"
            f"【再生成指示】前回の生成では次の単語がword_breakdownに独立エントリとして含まれていませんでした: {missing_str}\n"
            f"これらの単語を複合語の一部ではなく、単独で意味が成り立つ形で文中に使い、word_breakdownにも独立した項目として含めてください。"
        )

    raise RuntimeError(f"Failed after retries: {word}")


def load_progress() -> dict:
    if os.path.exists(PROGRESS_FILE):
        with open(PROGRESS_FILE) as f:
            return json.load(f)
    return {"completed_words": [], "sentences": []}


def save_progress(progress: dict) -> None:
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    with open(PROGRESS_FILE, "w") as f:
        json.dump(progress, f, ensure_ascii=False, indent=2)


def main() -> None:
    print("Loading freq_rank from GCS...")
    freq_rank = load_freq_rank()
    words = get_target_words(freq_rank)
    print(f"Target words: {len(words)} (rank < {MAX_FREQ_RANK})")

    progress = load_progress()
    completed = set(progress["completed_words"])
    all_sentences = progress["sentences"]

    remaining = [w for w in words if w not in completed]
    print(f"Already completed: {len(completed)}, remaining: {len(remaining)}")

    for i, word in enumerate(remaining):
        rank = freq_rank.get(word, -1)
        print(f"\n[{len(completed) + i + 1}/{len(words)}] {word} (rank={rank})")

        for s_idx in range(SENTENCES_PER_WORD):
            estimated_vocab = min(rank, 100) if rank >= 0 else 0
            try:
                start = time.time()
                sentence = generate_one(word, estimated_vocab, s_idx)
                elapsed = time.time() - start

                entry = {
                    "key_word": word,
                    "key_word_rank": rank,
                    "estimated_vocab": estimated_vocab,
                    "thai_text": sentence["thai_text"],
                    "pronunciation": sentence.get("pronunciation", ""),
                    "japanese_translation": sentence["japanese_translation"],
                    "word_breakdown": sentence.get("word_breakdown", []),
                    "context": sentence.get("context", {}),
                    "generation_tier": "free",
                }
                all_sentences.append(entry)
                print(f"  [{s_idx + 1}/{SENTENCES_PER_WORD}] OK ({elapsed:.1f}s): {sentence['thai_text'][:50]}")
            except Exception as exc:
                print(f"  [{s_idx + 1}/{SENTENCES_PER_WORD}] FAILED: {exc}")

        progress["completed_words"].append(word)
        progress["sentences"] = all_sentences
        save_progress(progress)

    os.makedirs(OUTPUT_DIR, exist_ok=True)
    with open(OUTPUT_FILE, "w") as f:
        json.dump(all_sentences, f, ensure_ascii=False, indent=2)

    print(f"\nDone! {len(all_sentences)} sentences saved to {OUTPUT_FILE}")


if __name__ == "__main__":
    main()
