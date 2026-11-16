"""動画の確認クイズ（単語→意味の4択）を例文の単語分解から作る。

正解は学習単語（key_word）の意味。ダミーは同じ例文のほかの語の意味から3つ選ぶ。
生成はしないので費用はかからない。並びは例文で決まる（同じ例文なら同じ問題）。

出力: <out>/quiz.json（QuizQuestion.fromJson の形）
"""

from __future__ import annotations

import argparse
import json
import random
import sys
from pathlib import Path

CHOICES = 4


def build_quiz(sentence: dict) -> dict | None:
    words = sentence.get("word_breakdown") or []
    key_word = sentence.get("key_word") or ""
    target = next((w for w in words if w.get("word") == key_word), None)
    if target is None or not (target.get("meaning") or "").strip():
        return None
    correct = target["meaning"].strip()

    # 同じ意味・空の意味は外す。順は例文の並びのまま重複を落とす。
    others: list[str] = []
    for word in words:
        meaning = (word.get("meaning") or "").strip()
        if word is target or not meaning or meaning == correct or meaning in others:
            continue
        others.append(meaning)
    if len(others) < CHOICES - 1:
        return None

    rng = random.Random(sentence.get("thai_text", ""))
    choices = [correct, *rng.sample(others, CHOICES - 1)]
    rng.shuffle(choices)

    thai = sentence.get("thai_text", "")
    return {
        "sentence_id": "x_post",
        "thai_text": thai,
        "blank_text": thai.replace(key_word, "___", 1),
        "correct_answer": key_word,
        "correct_answer_meaning": correct,
        "choices": choices,
        "choice_pronunciations": [],
        "pronunciation": target.get("pronunciation", ""),
        "explanation": "",
        "japanese_translation": sentence.get("japanese_translation", ""),
        "sentence_pronunciation": sentence.get("pronunciation", ""),
        "quiz_format": "meaning_choice",
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", default="build/x_post")
    args = parser.parse_args()

    out = Path(args.out)
    sentence = json.loads((out / "sentence.json").read_text(encoding="utf-8"))
    quiz = build_quiz(sentence)
    if quiz is None:
        print("学習単語の意味かダミーが足りず、クイズを作れない", file=sys.stderr)
        return 1
    (out / "quiz.json").write_text(
        json.dumps(quiz, ensure_ascii=False, indent=1), encoding="utf-8"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
