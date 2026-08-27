"""NLP 差分テスト用コーパスを抽出する。

2つのソースがある。既定は dict。

  dict       PyThaiNLP / TLTK にバンドルされた辞書（約8万語）。
             th2ipa や分割器が実際に引く辞書そのものなので、入力空間を
             ほぼ網羅する。Firestore 不要・決定的・CI で回せる。
             移植の正当性を保証するのはこちら。

  firestore  実際に生成された例文と、UVM に載っている語。
             辞書に無い借用語・固有名詞・記号混じりの実データが取れる。
             「実ユーザーの表示が変わらないこと」を追加で担保する。

使い方:
  cd functions/python
  python scripts/nlp_golden/extract_corpus.py --source dict \
    --out scripts/nlp_golden/data/corpus.jsonl

  GCLOUD_PROJECT=thai-memo-dev python scripts/nlp_golden/extract_corpus.py \
    --source firestore --out scripts/nlp_golden/data/corpus_fs.jsonl --limit 5000

出力: corpus.jsonl  {"kind": "sentence"|"word", "text": "..."}
"""

import argparse
import json
import os
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

DEFAULT_PROJECT = "thai-memo-dev"

# wordseq エントリの語区切り。タイ語の見出し語には現れない文字を使う。
WORDSEQ_SEP = "\u241f"

# タイ文字を1文字以上含む語だけを対象にする。辞書には英字の見出しも混ざる。
_THAI = re.compile(r"[฀-๿]")


def _db():
    import firebase_admin
    from firebase_admin import firestore

    if not firebase_admin._apps:
        firebase_admin.initialize_app(options={"projectId": os.environ["GCLOUD_PROJECT"]})
    return firestore.client()


def _site_packages() -> Path:
    import pythainlp

    return Path(pythainlp.__file__).resolve().parents[1]


def collect_dict() -> tuple[list[str], list[str]]:
    """バンドル辞書から語彙を集める。文は生成しない（辞書に文は無い）。"""
    sp = _site_packages()
    words: set[str] = set()

    # TLTK BEST.dict は cp874。th2ipa が引く辞書そのもの。
    best = sp / "tltk" / "BEST.dict"
    if best.exists():
        for line in best.read_text(encoding="cp874", errors="replace").splitlines():
            w = line.strip()
            if w and _THAI.search(w):
                words.add(w)

    # PyThaiNLP の単語辞書・音節辞書
    for name in ("words_th.txt", "syllables_th.txt"):
        path = sp / "pythainlp" / "corpus" / name
        if path.exists():
            for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
                w = line.strip()
                if w and _THAI.search(w):
                    words.add(w)

    # nlp.py の品詞判定は _POS_OVERRIDE -> ADJECTIVES -> unigram -> perceptron の
    # 4段階。辞書コーパスだけだと前2段にほとんど当たらない（実測 2000語中6語）
    # ので、確定辞書の見出し語を明示的に混ぜて全段を踏ませる。
    words |= _project_pos_words()

    return [], sorted(words)


def _project_pos_words() -> set[str]:
    """nlp.py が持つ品詞確定辞書の見出し語。"""
    out: set[str] = set()
    try:
        import nlp

        out |= set(nlp._POS_OVERRIDE)
    except Exception as exc:  # pragma: no cover
        print(f"  [warn] _POS_OVERRIDE を読めない: {exc}", file=sys.stderr)
    try:
        from pos_adjectives import ADJECTIVES

        out |= set(ADJECTIVES)
    except ImportError:
        pass
    return {w for w in out if w.strip()}


def collect_firestore(limit: int) -> tuple[list[str], list[str]]:
    """例文と単語を collection_group で横断的に集める。"""
    db = _db()
    sentences: set[str] = set()
    words: set[str] = set()

    # users/{uid}/sentences — 生成済み例文
    for doc in db.collection_group("sentences").limit(limit).stream():
        d = doc.to_dict() or {}
        thai = (d.get("thai_text") or d.get("thai") or "").strip()
        if thai:
            sentences.add(thai)
        for wb in d.get("word_breakdown") or []:
            w = (wb.get("thai") or wb.get("word") or "").strip()
            if w:
                words.add(w)

    # users/{uid}/uvm — 語彙モデルに載っている語（発音表記の同一性が最重要）
    for doc in db.collection_group("uvm").limit(limit).stream():
        w = (doc.id or "").strip()
        if w:
            words.add(w)

    return sorted(sentences), sorted(words)


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--out", required=True)
    p.add_argument("--source", choices=("dict", "firestore"), default="dict")
    p.add_argument("--limit", type=int, default=5000, help="firestore: コレクションごとの取得上限")
    p.add_argument("--sample", type=int, default=0, help="先頭N件に絞る（決定的に間引く）")
    p.add_argument(
        "--wordseq",
        type=int,
        default=0,
        help="単語列エントリを N 本生成する（perceptron の prev/prev2 連鎖を試すため）",
    )
    p.add_argument(
        "--sentences",
        type=int,
        default=0,
        help="辞書語を無空白で連結した擬似文を N 本生成する（分割器を突くため）",
    )
    args = p.parse_args()

    if args.source == "dict":
        sentences, words = collect_dict()
    else:
        os.environ.setdefault("GCLOUD_PROJECT", DEFAULT_PROJECT)
        sentences, words = collect_firestore(args.limit)

    if args.sample:
        # ソート済みリストから等間隔に取る。先頭だけだと文字コード順で偏る。
        def thin(xs: list[str]) -> list[str]:
            if len(xs) <= args.sample:
                return xs
            step = len(xs) / args.sample
            return [xs[int(i * step)] for i in range(args.sample)]

        sentences, words = thin(sentences), thin(words)

    # perceptron タガーは直前2語のタグを特徴量に使う（_get_features の
    # "i-1 tag" / "i-2 tag" / "i tag+i-2 tag"）。nlp.py:199 は文脈判定のため
    # 全単語をまとめて渡すので、単語1個ずつの検証ではこの経路が試されない。
    # 辞書から決定的に単語列を合成して穴を塞ぐ。タイ語として自然である必要は
    # なく、特徴量空間を踏むことが目的。
    # newmm は「辞書 + 最長一致 + TCC境界」なので、語を無空白で連結した文字列が
    # 最も曖昧で難しい入力になる（グラフが膨らみ _MAX_GRAPH_SIZE の打ち切りや
    # 候補なしフォールバックに入る）。辞書コーパスには文が無いので合成する。
    if args.sentences and words:
        span = 5
        step = max(1, len(words) // args.sentences)
        for i in range(args.sentences):
            start = (i * step) % max(1, len(words) - span)
            chunk = words[start : start + span]
            if len(chunk) >= 2:
                sentences.append("".join(chunk))
        sentences = sorted(set(sentences))

    seqs: list[str] = []
    if args.wordseq and words:
        span = 7
        step = max(1, len(words) // args.wordseq)
        for i in range(args.wordseq):
            start = (i * step) % max(1, len(words) - span)
            chunk = words[start : start + span]
            if len(chunk) >= 2:
                seqs.append(WORDSEQ_SEP.join(chunk))

    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    with out.open("w", encoding="utf-8") as f:
        for s in sentences:
            f.write(json.dumps({"kind": "sentence", "text": s}, ensure_ascii=False) + "\n")
        for w in words:
            f.write(json.dumps({"kind": "word", "text": w}, ensure_ascii=False) + "\n")
        for s in seqs:
            f.write(json.dumps({"kind": "wordseq", "text": s}, ensure_ascii=False) + "\n")

    src = args.source
    if src == "firestore":
        src += f"({os.environ['GCLOUD_PROJECT']})"
    print(
        f"source={src} sentences={len(sentences)} words={len(words)} "
        f"wordseq={len(seqs)} -> {out}",
        file=sys.stderr,
    )


if __name__ == "__main__":
    main()
