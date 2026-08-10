"""freq_rank から学習語彙にならない語を除去し、rank を連番で振り直すスクリプト。

除去対象:
  - functions/python/bound_morphemes.py の BOUND_MORPHEMES
    （น่า, การ, ริ … 単独で文に立てない拘束形態素）
  - functions/python/interjections.py の INTERJECTIONS
    （อ๋อ, เฮ้อ, โอ้ย … 単独で発話になる間投詞）
  - functions/python/non_vocab.py の NON_VOCAB
    （มั้ง, ซู, งี้ … 終助詞・人名断片・口語の崩れ表記）
これらを freq_rank から物理的に削除し、残った語を 1 から連番で振り直す。
rank に穴が空かないため、実行時コードでの除外フィルタが不要になる。

corpus 再生成 (build_freq_rank.py) 時は corpus_word_filter.py の
DENYLIST 経由で同じ語が落ちるため、このスクリプトは既存 JSON を
移行するための一度きりの用途。

【使い方】
    cd scripts
    python strip_denylist.py            # dry-run（差分表示のみ）
    python strip_denylist.py --write    # corpus/*.json を書き換え（.bak を残す）

書き換え後は ./upload_corpus.sh <project_id> で GCS に反映する。

【注意】
rank は estimated_vocab の尺度そのものなので、振り直すと既存ユーザーの
語彙レベルが実態より高く出る。ずれ幅は「その rank 以下にある除外語の数」。
"""

import argparse
import json
import shutil
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR.parent / "functions" / "python"))

from bound_morphemes import BOUND_MORPHEMES  # noqa: E402
from interjections import INTERJECTIONS  # noqa: E402
from non_vocab import NON_VOCAB  # noqa: E402

DENYLIST = set(BOUND_MORPHEMES) | set(INTERJECTIONS) | set(NON_VOCAB)

TARGETS = [
    SCRIPT_DIR / "corpus/freq_rank.json",
    SCRIPT_DIR / "corpus/freq_rank_top10000.json",
]


def strip(freq_rank: dict[str, int]) -> tuple[dict[str, int], list[tuple[int, str]]]:
    """除去対象語を除いて rank を 1 から振り直す。"""
    removed = sorted((r, w) for w, r in freq_rank.items() if w in DENYLIST)
    kept = sorted(
        ((r, w) for w, r in freq_rank.items() if w not in DENYLIST),
    )
    return {w: i + 1 for i, (_, w) in enumerate(kept)}, removed


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--write", action="store_true", help="ファイルを書き換える")
    args = parser.parse_args()

    for path in TARGETS:
        if not path.exists():
            print(f"skip (not found): {path}")
            continue

        with path.open(encoding="utf-8") as f:
            freq_rank = json.load(f)

        new_rank, removed = strip(freq_rank)
        print(f"\n{path.name}: {len(freq_rank)} → {len(new_rank)}語 (除外 {len(removed)})")
        print("  除外語(上位20): " + ", ".join(f"{w}:{r}" for r, w in removed[:20]))
        # ずれの確認用: 代表的な rank でどれだけ前倒しになるか
        for ev in (100, 200, 500, 1000, 3000):
            shift = sum(1 for r, _ in removed if r <= ev)
            print(f"  rank {ev} のずれ: -{shift}")

        if not args.write:
            continue

        shutil.copy2(path, path.with_suffix(".json.bak"))
        with path.open("w", encoding="utf-8") as f:
            json.dump(new_rank, f, ensure_ascii=False)
        print(f"  書き換え完了（バックアップ: {path.name}.bak）")


if __name__ == "__main__":
    main()
