"""TLTK / PyThaiNLP のデータを Go が読める形式に書き出す。

th2ipa の移植に必要なのは4ファイルだけ（NER / POS tagger / sent_segment 等
10MB 分は g2p の経路から到達しないので出力しない）。

  sylrule.lts       cp874  音節→音素の規則表。これが音韻規則の本体
  BEST.dict         cp874  タイ語辞書（既知語判定に使う）
  sylform_var.pick  pickle 音節形のバリエーション
  sylseg.3g         pickle 音節 trigram 統計 {(X,Y,Z): count}

sylseg.3g からは TriCount だけを出す。BiCount / Count / Type / BiType は
read_stat が TriCount から導出しているだけなので、Go 側も同じ導出をすればよい
（tltk/th2ipa.py:1421-1433）。

出力はすべて UTF-8 の JSON / テキスト。Go 側は embed で静的バイナリに含める。

使い方:
  cd functions/python
  .venv/bin/python scripts/nlp_golden/export_tltk_data.py --out ../go/internal/thainlp/data
"""

import argparse
import json
import pickle
import sys
from pathlib import Path

# nlp.py / pos_adjectives.py を import するため functions/python を通す
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))


def _site_packages() -> Path:
    import pythainlp

    return Path(pythainlp.__file__).resolve().parents[1]


def _write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")
    print(f"  {path.name:24s} {len(text.encode('utf-8')):>10,} bytes", file=sys.stderr)


def _write_gz(path: Path, text: str) -> None:
    import gzip

    path.parent.mkdir(parents=True, exist_ok=True)
    raw = text.encode("utf-8")
    # mtime=0 で出力を決定的にする（再実行で差分が出ないように）
    with gzip.GzipFile(path, "wb", compresslevel=9, mtime=0) as f:
        f.write(raw)
    print(
        f"  {path.name:24s} {path.stat().st_size:>10,} bytes (raw {len(raw):,})",
        file=sys.stderr,
    )


def export_tltk(sp: Path, out: Path) -> None:
    tltk = sp / "tltk"

    # --- cp874 のテキストはそのまま UTF-8 に転写する -------------------------
    for name in ("sylrule.lts", "BEST.dict"):
        src = tltk / name
        if not src.exists():
            print(f"  [skip] {name} が無い", file=sys.stderr)
            continue
        _write(out / name, src.read_text(encoding="cp874", errors="replace"))

    # --- trigram 統計は JSON Lines へ（gzip 圧縮して埋め込む）---------------
    # キーには \t や \x1f が区切り記号として実際に含まれるので、TSV は使えない。
    # 1行 ["X","Y","Z",count] の JSON にしてエスケープを処理系に任せる。
    src = tltk / "sylseg.3g"
    if src.exists():
        with src.open("rb") as f:
            tri = pickle.load(f)
        lines = [
            json.dumps([k[0], k[1], k[2], tri[k]], ensure_ascii=False) for k in sorted(tri)
        ]
        _write_gz(out / "sylseg_3g.jsonl.gz", "\n".join(lines) + "\n")

    # --- pickle は JSON へ ---------------------------------------------------
    src = tltk / "sylform_var.pick"
    if src.exists():
        with src.open("rb") as f:
            sylvar = pickle.load(f)
        # キーがタプルの場合があるので文字列に正規化する
        norm = {
            ("\t".join(map(str, k)) if isinstance(k, tuple) else str(k)): v
            for k, v in sylvar.items()
        }
        _write(out / "sylform_var.json", json.dumps(norm, ensure_ascii=False, sort_keys=True))


def export_pythainlp(sp: Path, out: Path) -> None:
    corpus = sp / "pythainlp" / "corpus"
    for name in ("words_th.txt", "syllables_th.txt"):
        src = corpus / name
        if src.exists():
            _write(out / name, src.read_text(encoding="utf-8", errors="replace"))


def export_pos(sp: Path, out: Path) -> None:
    """POS タグ付けに必要なモデルとマッピング表を出す。

    使うのは2経路だけ（nlp.py:183, 199）:
      unigram + tud        -> 単なる辞書引き
      perceptron + orchid_ud -> averaged perceptron + ORCHID→UD 変換
    """
    corpus = sp / "pythainlp" / "corpus"

    src = corpus / "pos_tud_unigram.json"
    if src.exists():
        # utf-8-sig で読んで BOM を落とす
        _write(out / "pos_tud_unigram.json", src.read_text(encoding="utf-8-sig"))

    src = corpus / "pos_orchid_perceptron.json"
    if src.exists():
        _write_gz(out / "pos_orchid_perceptron.json.gz", src.read_text(encoding="utf-8-sig"))

    from pythainlp.tag import orchid

    _write(
        out / "orchid_maps.json",
        json.dumps(
            {
                "char_to_escape": orchid.CHAR_TO_ESCAPE,
                "escape_to_char": orchid.ESCAPE_TO_CHAR,
                "to_ud": orchid.TO_UD,
            },
            ensure_ascii=False,
            sort_keys=True,
        ),
    )


def export_sylrule(out: Path) -> None:
    """th2ipa の音韻規則テーブルを書き出す。

    read_sylpattern が sylrule.lts から組み立てた PRON（正規表現 -> 音素列）と、
    コード中にベタ書きされている stable / AK / EngAbbr を出す。

    PRON は **挿入順が意味を持つ**（sylparse の `for f in PRON:` が
    その順で走査し、PRONUN への追加順が後段の SelectPhones に効く）。
    JSON オブジェクトでは順序を保証できないので配列で出す。
    """
    sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
    import pronunciation as _p

    m = _p._TH2IPA
    _write(
        out / "sylrule_pron.json",
        json.dumps(
            {
                # [[pattern, [phone, ...]], ...] 挿入順のまま
                "pron": [[k, list(v)] for k, v in m.PRON.items()],
                "stable": {k: dict(v) for k, v in m.stable.items()},
                "ak": dict(m.AK),
                "eng_abbr": list(m.EngAbbr),
            },
            ensure_ascii=False,
        ),
    )


def export_probphone(out: Path) -> None:
    """wordparse / ProbPhone が引くテーブルを書き出す。

    PhSTrigram.sts から read_PhSTrigram が組み立てた8つの統計と、TDICT。

    TDICT は BEST.dict ではなく thdict 由来（th2ipa.py:1524 の read_thdict）。
    語数が違う（BEST.dict 33,200 / TDICT 65,431）ので取り違えないこと。

    導出済みの実体をそのまま出す。導出手順を Go で書き直すと差が入りうる。
    """
    sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
    import pronunciation as _p

    m = _p._TH2IPA

    _write_gz(
        out / "tdict.txt.gz",
        "\n".join(sorted(m.TDICT)) + "\n",
    )

    def dump(name: str, arity: int) -> None:
        tbl = getattr(m, name)
        lines = []
        for k in sorted(tbl):
            key = list(k) if isinstance(k, tuple) else [k]
            if len(key) != arity:
                raise ValueError(f"{name}: キー長が {len(key)}、想定 {arity}")
            lines.append(json.dumps(key + [tbl[k]], ensure_ascii=False))
        _write_gz(out / f"{name}.jsonl.gz", "\n".join(lines) + "\n")

    dump("PhSTrigram", 4)
    dump("FrmSTrigram", 3)
    dump("PhSBigram", 3)
    dump("FrmSBigram", 2)
    dump("PhSUnigram", 2)
    dump("FrmSUnigram", 1)
    dump("AbsUnigram", 2)
    dump("AbsFrmSUnigram", 1)


def export_project_pos(out: Path) -> None:
    """nlp.py が持つ品詞判定用の辞書を書き出す。

    ライブラリではなくプロジェクト側のデータなので、書き出し経由にして
    Python と Go がずれないようにする。_POS_OVERRIDE は手で保守され、
    ADJECTIVES は build_adjective_dict.py が生成する。
    """
    import nlp

    try:
        from pos_adjectives import ADJECTIVES
    except ImportError:
        ADJECTIVES = frozenset()

    _write(
        out / "pos_project.json",
        json.dumps(
            {
                "pos_tag_map": nlp._POS_TAG_MAP,
                "pos_override": nlp._POS_OVERRIDE,
                "adjectives": sorted(ADJECTIVES),
            },
            ensure_ascii=False,
            sort_keys=True,
        ),
    )


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--out", required=True, help="出力ディレクトリ")
    args = p.parse_args()

    sp = _site_packages()
    out = Path(args.out).resolve()

    print(f"TLTK -> {out}", file=sys.stderr)
    export_tltk(sp, out)
    print(f"PyThaiNLP -> {out}", file=sys.stderr)
    export_pythainlp(sp, out)
    print(f"POS -> {out}", file=sys.stderr)
    export_pos(sp, out)
    export_project_pos(out)
    print(f"sylrule -> {out}", file=sys.stderr)
    export_sylrule(out)
    print(f"ProbPhone -> {out}", file=sys.stderr)
    export_probphone(out)


if __name__ == "__main__":
    main()
