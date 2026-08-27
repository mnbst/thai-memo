"""コーパスに対して現行 Python 実装を流し、golden.jsonl を固定する。

Go 移植の正解データ。移植前にこれをコミットしておき、Go 実装が
100% 一致するまでリリースしない。

使い方:
  cd functions/python
  python scripts/nlp_golden/gen_golden.py \
    --corpus scripts/nlp_golden/data/corpus.jsonl \
    --out scripts/nlp_golden/data/golden.jsonl

出力: golden.jsonl  {"tier": 1|2, "api": "...", "in": <入力>, "out": <出力>}
      api, in でソート済み。差分を git diff で読めるようにするため。
"""

import argparse
import json
import multiprocessing as mp
import sys
from pathlib import Path

# 現行実装が例外を投げたことを表す番兵。Go 側もこの値を出力すれば一致とみなす。
ERROR_SENTINEL = {"__error__": True}

# 各呼び出し前に TLTK の統計を初期状態へ戻すか。False にすると現行の本番と同じ
# 「履歴依存」の挙動になる。--impure で切り替える。
PURE = True

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

# ---------------------------------------------------------------------------
# tier1: 呼び出し側が依存する公開API。1件でも不一致なら移植は失敗。
# ---------------------------------------------------------------------------
from nlp import get_pos_japanese, segment_syllables  # noqa: E402
from pronunciation import thai_to_pronunciation  # noqa: E402
from word_gap import _tokenize_words  # noqa: E402

# ---------------------------------------------------------------------------
# tier2: 不一致の原因を切り分けるためのプリミティブ。単体では FAIL 判定しない。
# ---------------------------------------------------------------------------
import pronunciation as _pron  # noqa: E402
from pythainlp_fast import pos_tag, subword_tokenize  # noqa: E402


def _th2ipa(text: str) -> str:
    return _pron._TH2IPA.th2ipa(text).strip()


# ---------------------------------------------------------------------------
# TLTK の状態リセット
#
# th2ipa は推論中に自分の n-gram 統計を書き換える（tltk/th2ipa.py:893-897 で
# 未知バイグラムに加算スムージングをグローバル変数の破壊的更新で適用している）。
# 結果として「そのプロセスが直前に何を処理したか」で出力が変わり、純関数ではない。
#
# golden をプロセス分割や実行順に依存させないため、各呼び出しの前に
# 統計を初期状態へ戻す。実測でオーバーヘッドは 6% 程度。
# ---------------------------------------------------------------------------
_TLTK = _pron._TH2IPA


def _tltk_snapshot() -> tuple[dict, dict, float]:
    return (dict(_TLTK.BiCount), dict(_TLTK.Count), _TLTK.TotalWord)


def _tltk_restore(snap: tuple[dict, dict, float]) -> None:
    bi, cnt, total = snap
    _TLTK.BiCount.clear()
    _TLTK.BiCount.update(bi)
    _TLTK.Count.clear()
    _TLTK.Count.update(cnt)
    _TLTK.TotalWord = total


# wordseq エントリの語区切り。extract_corpus.WORDSEQ_SEP と同じ。
WORDSEQ_SEP = "\u241f"


def _pos_seq_perceptron(text: str):
    """単語列をまとめて perceptron に渡す。prev/prev2 の連鎖を試すため。

    nlp.py:199 は「文脈判定のため全単語を渡す」ので、この経路が本番の実挙動。
    """
    words = [w for w in text.split(WORDSEQ_SEP) if w]
    return pos_tag(words, engine="perceptron", corpus="orchid_ud")


def _pos_seq_unigram(text: str):
    words = [w for w in text.split(WORDSEQ_SEP) if w]
    return pos_tag(words, engine="unigram", corpus="tud")


# --- th2ipa の中間層 ------------------------------------------------------
# th2ipa は preprocess -> sylparse -> wordparse -> SelectPhones の多段構成。
# 端から端まで一致しないときに、どの段で壊れたかを切り分けるための診断。
# 移植も段ごとに進められる。


def _sylparse(text: str) -> str:
    """音節分割＋各音節の候補音素を返す段（th2ipa.py:121）。"""
    return _pron._TH2IPA.sylparse(text)


def _wordparse(text: str) -> str:
    """sylparse の結果から語を組み立て音素列を確定する段（th2ipa.py:498）。"""
    return _pron._TH2IPA.wordparse(_pron._TH2IPA.sylparse(text))


def _word_tokenize(text: str) -> list[str]:
    from pythainlp.tokenize import word_tokenize

    return [w for w in word_tokenize(text) if w.strip()]


# (tier, api名, 関数, 適用する corpus の kind)
CASES = [
    (1, "thai_to_pronunciation", thai_to_pronunciation, ("sentence", "word")),
    (1, "segment_syllables", segment_syllables, ("word",)),
    (1, "get_pos_japanese", get_pos_japanese, ("word",)),
    (1, "tokenize_words", _tokenize_words, ("sentence",)),
    (2, "th2ipa", _th2ipa, ("sentence", "word")),
    (2, "subword_tokenize", lambda w: subword_tokenize(w, engine="dict"), ("word",)),
    (
        2,
        "pos_tag_unigram_tud",
        lambda w: pos_tag([w], engine="unigram", corpus="tud"),
        ("word",),
    ),
    (
        2,
        "pos_tag_perceptron_orchid_ud",
        lambda w: pos_tag([w], engine="perceptron", corpus="orchid_ud"),
        ("word",),
    ),
    (2, "sylparse", _sylparse, ("word",)),
    (2, "wordparse", _wordparse, ("word",)),
    (2, "pos_tag_seq_perceptron_orchid_ud", _pos_seq_perceptron, ("wordseq",)),
    (2, "pos_tag_seq_unigram_tud", _pos_seq_unigram, ("wordseq",)),
]


def _run_chunk(entries: list[dict]) -> list[dict]:
    """コーパスの一部について全 API を回す。ワーカープロセスで実行される。

    NLP モデルのロードはプロセスごとに1回だけ起きる（import 時）。
    したがってチャンクは十分大きく取り、プロセス数は控えめにする。
    """
    rows: list[dict] = []
    snap = _tltk_snapshot() if PURE else None
    for tier, api, fn, kinds in CASES:
        for entry in entries:
            if entry["kind"] not in kinds:
                continue
            text = entry["text"]
            if snap is not None:
                _tltk_restore(snap)
            try:
                out = fn(text)
            except Exception:
                out = ERROR_SENTINEL
            rows.append({"tier": tier, "api": api, "in": text, "out": out})
    return rows


def _generate(corpus: list[dict], jobs: int, stride: bool) -> list[dict]:
    """コーパス全体を処理する。

    `stride` はワーカーへの割り当て方。True なら1件おき、False なら連続ブロック。
    th2ipa が状態を持つため、割り当てを変えると一部の出力が変わる。
    その差を決定性チェックに使う。
    """
    if jobs <= 1 or len(corpus) < 200:
        return _run_chunk(corpus)
    if stride:
        chunks = [corpus[i::jobs] for i in range(jobs)]
    else:
        size = -(-len(corpus) // jobs)
        chunks = [corpus[i : i + size] for i in range(0, len(corpus), size)]
    with mp.get_context("fork").Pool(len(chunks)) as pool:
        return [r for part in pool.map(_run_chunk, chunks) for r in part]


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--corpus", required=True)
    p.add_argument("--out", required=True)
    p.add_argument(
        "--jobs",
        type=int,
        default=max(1, (mp.cpu_count() or 2) - 1),
        help="並列プロセス数。1 で逐次実行",
    )
    p.add_argument(
        "--check-determinism",
        action="store_true",
        help="分割を変えて2回流し、揺れる入力に unstable 印を付ける（所要時間は倍）",
    )
    p.add_argument(
        "--impure",
        action="store_true",
        help="TLTK の状態リセットを行わない（本番と同じ履歴依存の挙動を再現する）",
    )
    args = p.parse_args()

    global PURE
    PURE = not args.impure

    corpus: list[dict] = []
    with open(args.corpus, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line:
                corpus.append(json.loads(line))

    rows = _generate(corpus, args.jobs, stride=True)

    unstable: set[tuple[str, str]] = set()
    if args.check_determinism:
        # TLTK の th2ipa は推論中に自身の n-gram 統計を更新するため、純関数ではない。
        # 同じ入力でも「そのプロセスが直前に何を処理したか」で結果が変わりうる。
        # 分割の仕方を変えて2回流し、揺れる入力を洗い出して印を付ける。
        # 揺れる入力は Python 側で再現性が無いので、Go にも一致を要求できない。
        rows2 = _generate(corpus, args.jobs, stride=False)
        m2 = {(r["api"], r["in"]): r["out"] for r in rows2}
        for r in rows:
            key = (r["api"], r["in"])
            if key in m2 and m2[key] != r["out"]:
                unstable.add(key)
        for r in rows:
            if (r["api"], r["in"]) in unstable:
                r["unstable"] = True

    errors = sum(1 for r in rows if r["out"] == ERROR_SENTINEL)
    rows.sort(key=lambda r: (r["api"], r["in"]))

    out_path = Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with out_path.open("w", encoding="utf-8") as f:
        for r in rows:
            f.write(json.dumps(r, ensure_ascii=False, sort_keys=True) + "\n")

    tier1 = sum(1 for r in rows if r["tier"] == 1)
    msg = f"corpus={len(corpus)} rows={len(rows)} (tier1={tier1}) errors={errors}"
    if args.check_determinism:
        u1 = sum(1 for r in rows if r.get("unstable") and r["tier"] == 1)
        msg += f" unstable={len(unstable)} (tier1={u1})"
    print(f"{msg} -> {out_path}", file=sys.stderr)


if __name__ == "__main__":
    main()
