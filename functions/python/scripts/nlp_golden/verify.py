"""候補実装（Go）の出力を golden と突き合わせ、差分を報告する。

tier1 が1件でも不一致なら exit 1。tier2 の不一致は原因切り分け用に出すだけ。

使い方:
  go run ./cmd/nlpdump --corpus .../corpus.jsonl > candidate.jsonl
  python scripts/nlp_golden/verify.py \
    --golden scripts/nlp_golden/data/golden.jsonl \
    --candidate candidate.jsonl [--show 20]
"""

import argparse
import json
import sys
from collections import defaultdict


def load(path: str) -> dict[tuple[str, str], dict]:
    rows: dict[tuple[str, str], dict] = {}
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            r = json.loads(line)
            rows[(r["api"], r["in"])] = r
    return rows


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--golden", required=True)
    p.add_argument("--candidate", required=True)
    p.add_argument("--show", type=int, default=10, help="api ごとに表示する不一致の件数")
    args = p.parse_args()

    golden = load(args.golden)
    cand = load(args.candidate)

    missing = sorted(set(golden) - set(cand))
    extra = sorted(set(cand) - set(golden))

    mismatches: dict[str, list[tuple[str, object, object]]] = defaultdict(list)
    total: dict[str, int] = defaultdict(int)
    missing_by_api: dict[str, int] = defaultdict(int)
    unstable_by_api: dict[str, int] = defaultdict(int)
    tier_of: dict[str, int] = {}

    for key, g in golden.items():
        api, inp = key
        total[api] += 1
        tier_of[api] = g["tier"]
        c = cand.get(key)
        if c is None:
            # 欠落も不一致として数える。候補が黙って出力を省いたのを
            # 「一致」と読ませないため。
            missing_by_api[api] += 1
            continue
        if c["out"] == g["out"]:
            continue
        if g.get("unstable"):
            # Python 側でも処理順によって揺れる入力。再現性が無いものに
            # 一致を要求しても意味がないので、FAIL にはせず件数だけ出す。
            unstable_by_api[api] += 1
            continue
        mismatches[api].append((inp, g["out"], c["out"]))

    # --- レポート ---------------------------------------------------------
    print(f"golden={len(golden)} candidate={len(cand)}")
    if missing:
        print(f"\n[!] 候補に無いケース: {len(missing)}")
        for api, inp in missing[: args.show]:
            print(f"    {api}  {inp!r}")
    if extra:
        print(f"\n[!] golden に無いケース: {len(extra)}")
        for api, inp in extra[: args.show]:
            print(f"    {api}  {inp!r}")

    failed_tier1 = False
    for tier in (1, 2):
        apis = sorted(a for a in total if tier_of[a] == tier)
        if not apis:
            continue
        print(f"\n=== tier{tier} {'(契約層)' if tier == 1 else '(診断層)'} ===")
        for api in apis:
            miss = missing_by_api[api]
            n = len(mismatches[api]) + miss
            ok = total[api] - n
            rate = 100.0 * ok / total[api] if total[api] else 100.0
            mark = "OK " if n == 0 else "NG "
            note = f"  欠落{miss}件" if miss else ""
            if unstable_by_api[api]:
                note += f"  unstable{unstable_by_api[api]}件(除外)"
            print(f"{mark}{api:32s} {ok:6d}/{total[api]:<6d} ({rate:6.2f}%){note}")
            if n and tier == 1:
                failed_tier1 = True
            for inp, want, got in mismatches[api][: args.show]:
                print(f"      in   {inp!r}")
                print(f"      want {want!r}")
                print(f"      got  {got!r}")
            shown = len(mismatches[api])
            if shown > args.show:
                print(f"      ... 他 {shown - args.show} 件")

    if missing or failed_tier1:
        print("\nFAIL: tier1 に不一致がある（または候補が不完全）。リリース不可。")
        sys.exit(1)
    print("\nPASS: tier1 完全一致。")


if __name__ == "__main__":
    main()
