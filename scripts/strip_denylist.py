"""freq_rank から学習語彙にならない語を除去し、rank を連番で振り直すスクリプト。

除去対象は word_denylist.json のうち `_strip_freq_rank: true` の分類。
語として成立していない語（断片・誤記・固有名詞）だけを対象にする。
王室・性的・罵倒などの分類は方針の話なので freq_rank からは落とさない
（uvm/excluded.go の「予防的に語を足さない」に合わせる）。

freq_rank の語は UVM がそのまま出題・ターゲット語にするので、語でない語が
残っていると例文が作れない。静的コーパスの除外リストと同じ判断が要る。

【使い方】
    cd scripts
    python strip_denylist.py            # dry-run（差分表示のみ）
    python strip_denylist.py --write    # corpus/*.json を書き換え（.bak を残す）

書き換え後は ./upload_corpus.sh <project_id> で GCS に反映する。
vocab_words.json は vocab_embeddings.npy と行が対応するので触らないこと。

【注意】
rank は estimated_vocab の尺度そのものなので、振り直すと既存ユーザーの
語彙レベルが実態より高く出る。ずれ幅は「その rank 以下にある除外語の数」。
"""

import argparse
import json
import shutil
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
DENYLIST_PATH = SCRIPT_DIR / "word_denylist.json"

TARGETS = [
    SCRIPT_DIR / "corpus/freq_rank.json",
    SCRIPT_DIR / "corpus/freq_rank_top10000.json",
]


def load_denylist() -> set[str]:
    with DENYLIST_PATH.open(encoding="utf-8") as f:
        data = json.load(f)
    words: set[str] = set()
    for key, group in data.items():
        if key.startswith("_") or not group.get("_strip_freq_rank"):
            continue
        words |= set(group["words"])
    return words


def strip(
    freq_rank: dict[str, int], denylist: set[str]
) -> tuple[dict[str, int], list[tuple[int, str]]]:
    """除去対象語を除いて rank を 1 から振り直す。"""
    removed = sorted((r, w) for w, r in freq_rank.items() if w in denylist)
    kept = sorted((r, w) for w, r in freq_rank.items() if w not in denylist)
    return {w: i + 1 for i, (_, w) in enumerate(kept)}, removed


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--write", action="store_true", help="ファイルを書き換える")
    args = parser.parse_args()

    denylist = load_denylist()
    print(f"除去対象 {len(denylist)}語（word_denylist.json の _strip_freq_rank）")

    for path in TARGETS:
        if not path.exists():
            print(f"skip (not found): {path}")
            continue

        with path.open(encoding="utf-8") as f:
            freq_rank = json.load(f)

        new_rank, removed = strip(freq_rank, denylist)
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
