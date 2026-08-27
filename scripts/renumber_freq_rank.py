"""freq_rank の rank を 1 からの連番に振り直すスクリプト。

【なぜ必要か】
uvm.moving_avg は「freq_rank は拘束形態素を除いた連番なので、rank に穴はない」
という前提で書かれている。穴があると、その rank は UVM に登録されていても
常に UNKNOWN_WORD_P (0.4) として数えられ、周辺 ±10 の平均習熟度が
実態より低く出る。結果として estimated_vocab が本来より低く止まる。

語の増減はしない。順序も変えない。空いた番号を詰めるだけ。
語を除きたい場合は strip_denylist.py を使うこと。

【使い方】
    cd scripts
    python renumber_freq_rank.py            # dry-run（穴と影響の表示のみ）
    python renumber_freq_rank.py --write    # 書き換え（.renumber.bak を残す）

書き換え後は ./upload_corpus.sh <project_id> で GCS に反映する。

【注意】
rank は estimated_vocab の尺度そのもの。振り直すと穴より後ろの語が
1つずつ前倒しになるため、既存ユーザーの estimated_vocab がわずかに動く。
"""

import argparse
import json
import shutil
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent

TARGETS = [
    SCRIPT_DIR / "corpus/freq_rank.json",
    SCRIPT_DIR / "corpus/freq_rank_top10000.json",
]


def find_gaps(freq_rank: dict[str, int]) -> list[int]:
    """欠番の一覧を返す。"""
    ranks = set(freq_rank.values())
    if not ranks:
        return []
    return sorted(set(range(min(ranks), max(ranks) + 1)) - ranks)


def renumber(freq_rank: dict[str, int]) -> dict[str, int]:
    """現在の rank 順を保ったまま 1 から振り直す。"""
    ordered = sorted(freq_rank.items(), key=lambda item: item[1])
    return {word: i + 1 for i, (word, _) in enumerate(ordered)}


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

        gaps = find_gaps(freq_rank)
        ranks = sorted(freq_rank.values())
        print(f"\n{path.name}: {len(freq_rank)}語 rank {ranks[0]}..{ranks[-1]}")

        if not gaps:
            print("  欠番なし。振り直し不要。")
            continue

        print(f"  欠番 {len(gaps)} 件: "
              + ", ".join(str(g) for g in gaps[:20])
              + (" ..." if len(gaps) > 20 else ""))

        new_rank = renumber(freq_rank)

        # 重複が無いこと（順序を保てているか）の確認
        assert len(set(new_rank.values())) == len(new_rank), "振り直しで重複が出た"
        assert not find_gaps(new_rank), "振り直しても穴が残っている"

        # 代表的な rank でどれだけ前倒しになるか
        for ev in (100, 200, 500, 1000, 3000):
            shift = sum(1 for g in gaps if g <= ev)
            if shift:
                print(f"  rank {ev} のずれ: -{shift}")

        # 語の増減が無いこと
        assert set(new_rank) == set(freq_rank), "語が増減した"

        if not args.write:
            continue

        backup = path.with_suffix(".json.renumber.bak")
        shutil.copy2(path, backup)
        with path.open("w", encoding="utf-8") as f:
            json.dump(new_rank, f, ensure_ascii=False)
        print(f"  書き換え完了（バックアップ: {backup.name}）")


if __name__ == "__main__":
    main()
