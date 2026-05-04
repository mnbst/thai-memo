"""Backfill users/*/sentences/* key_word_pronunciation in prod Firestore.

Usage:
  cd functions/python
  .venv/bin/python ../../scripts/backfill_prod_key_word_pronunciation.py
  .venv/bin/python ../../scripts/backfill_prod_key_word_pronunciation.py --apply
"""

from __future__ import annotations

import argparse
import os
import sys
import unicodedata
from dataclasses import dataclass

import firebase_admin
from firebase_admin import firestore

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
FUNCTIONS_PYTHON = os.path.join(ROOT, "functions", "python")
if FUNCTIONS_PYTHON not in sys.path:
    sys.path.insert(0, FUNCTIONS_PYTHON)

from pronunciation import thai_to_pronunciation  # noqa: E402

PROJECT_ID = "thai-memo-prod"
BATCH_SIZE = 450
PROGRESS_INTERVAL = 500


@dataclass
class Stats:
    checked: int = 0
    missing: int = 0
    updated: int = 0
    skipped_no_key_word: int = 0
    skipped_conversion_failed: int = 0
    missing_sentence_pronunciation: int = 0
    not_contained: int = 0


def needs_backfill(data: dict) -> bool:
    value = data.get("key_word_pronunciation")
    return not isinstance(value, str) or not value.strip()


def get_pronunciation_from_breakdown(data: dict, key_word: str) -> str:
    for item in data.get("word_breakdown", []) or []:
        if not isinstance(item, dict):
            continue
        if (item.get("word") or "").strip() == key_word:
            pronunciation = item.get("pronunciation")
            if isinstance(pronunciation, str) and pronunciation.strip():
                return pronunciation.strip()
    return ""


def build_key_word_pronunciation(data: dict) -> str:
    key_word = data.get("key_word")
    if not isinstance(key_word, str) or not key_word.strip():
        return ""

    key_word = key_word.strip()
    return get_pronunciation_from_breakdown(data, key_word) or thai_to_pronunciation(
        key_word
    ).strip()


def normalize_pronunciation(value: str) -> str:
    return " ".join(unicodedata.normalize("NFC", value).strip().lower().split())


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--apply",
        action="store_true",
        help="Write missing key_word_pronunciation values to prod Firestore.",
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=0,
        help="Check only the first N sentence docs. Useful for verification.",
    )
    parser.add_argument(
        "--check-contained",
        action="store_true",
        help="Only verify key_word_pronunciation is included in pronunciation.",
    )
    args = parser.parse_args()

    os.environ["GOOGLE_CLOUD_PROJECT"] = PROJECT_ID
    app = firebase_admin.initialize_app(options={"projectId": PROJECT_ID})
    db = firestore.client()
    dry_run = not args.apply

    stats = Stats()
    batch = db.batch()
    batch_pending = 0
    examples: list[tuple[str, str, str]] = []
    containment_examples: list[tuple[str, str, str, str, str, str]] = []

    query = db.collection_group("sentences")
    if args.limit > 0:
        query = query.limit(args.limit)

    if args.check_contained and args.apply:
        parser.error("--check-contained cannot be combined with --apply")

    mode = (
        "check-contained"
        if args.check_contained
        else "apply"
        if args.apply
        else "dry-run"
    )
    print("Backfill mode:", mode, flush=True)
    print(f"Project: {PROJECT_ID}", flush=True)
    print("Scanning users/*/sentences/* ...", flush=True)

    for doc in query.stream(timeout=120):
        stats.checked += 1
        if stats.checked % PROGRESS_INTERVAL == 0:
            action = (
                "not_contained"
                if args.check_contained
                else "updated"
                if args.apply
                else "would_update"
            )
            value = stats.not_contained if args.check_contained else stats.updated
            print(
                f"progress checked={stats.checked} missing={stats.missing} "
                f"{action}={value}",
                flush=True,
            )
        data = doc.to_dict() or {}

        if args.check_contained:
            key_word = data.get("key_word")
            key_pronunciation = data.get("key_word_pronunciation")
            sentence_pronunciation = data.get("pronunciation")

            if not isinstance(key_word, str) or not key_word.strip():
                stats.skipped_no_key_word += 1
                continue
            if not isinstance(key_pronunciation, str) or not key_pronunciation.strip():
                stats.missing += 1
                continue
            if (
                not isinstance(sentence_pronunciation, str)
                or not sentence_pronunciation.strip()
            ):
                stats.missing_sentence_pronunciation += 1
                continue

            normalized_key_pronunciation = normalize_pronunciation(key_pronunciation)
            normalized_sentence_pronunciation = normalize_pronunciation(
                sentence_pronunciation
            )
            if normalized_key_pronunciation not in normalized_sentence_pronunciation:
                stats.not_contained += 1
                if len(containment_examples) < 20:
                    containment_examples.append(
                        (
                            doc.reference.path,
                            str(data.get("thai_text") or ""),
                            key_word.strip(),
                            key_pronunciation.strip(),
                            sentence_pronunciation.strip(),
                            str(data.get("japanese_translation") or ""),
                        )
                    )
            continue

        if not needs_backfill(data):
            continue

        stats.missing += 1
        key_word = data.get("key_word")
        if not isinstance(key_word, str) or not key_word.strip():
            stats.skipped_no_key_word += 1
            continue

        try:
            pronunciation = build_key_word_pronunciation(data)
        except Exception as exc:
            stats.skipped_conversion_failed += 1
            print(f"conversion failed: {doc.reference.path}: {key_word!r}: {exc}")
            continue

        if not pronunciation:
            stats.skipped_conversion_failed += 1
            continue

        if len(examples) < 10:
            examples.append((doc.reference.path, key_word.strip(), pronunciation))

        if args.apply:
            batch.update(doc.reference, {"key_word_pronunciation": pronunciation})
            batch_pending += 1
            if batch_pending >= BATCH_SIZE:
                batch.commit()
                batch = db.batch()
                batch_pending = 0

        stats.updated += 1

    if args.apply and batch_pending:
        batch.commit()

    print(f"Checked: {stats.checked}")
    if args.check_contained:
        print(f"Missing key_word_pronunciation: {stats.missing}")
        print(f"Missing pronunciation: {stats.missing_sentence_pronunciation}")
        print(f"Skipped without key_word: {stats.skipped_no_key_word}")
        print(f"Not contained: {stats.not_contained}")
        if containment_examples:
            print("\nNot contained examples:")
            for (
                path,
                thai_text,
                key_word,
                key_pronunciation,
                sentence_pronunciation,
                japanese_translation,
            ) in containment_examples:
                print(f"  {path}")
                print(f"    thai_text: {thai_text}")
                print(f"    key_word: {key_word}")
                print(f"    key_word_pronunciation: {key_pronunciation}")
                print(f"    pronunciation: {sentence_pronunciation}")
                print(f"    japanese_translation: {japanese_translation}")

        firebase_admin.delete_app(app)
        return 0

    print(f"Missing key_word_pronunciation: {stats.missing}")
    print(f"{'Updated' if args.apply else 'Would update'}: {stats.updated}")
    print(f"Skipped without key_word: {stats.skipped_no_key_word}")
    print(f"Skipped conversion failed: {stats.skipped_conversion_failed}")
    if examples:
        print("\nExamples:")
        for path, key_word, pronunciation in examples:
            print(f"  {path}: {key_word} -> {pronunciation}")

    firebase_admin.delete_app(app)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
