"""ja の例文バンク・プールから ko 版を作る（タイ語の文は ja と共通、訳だけ韓国語）。

韓国語版は ja と同じタイ語の文を出す（docs/design_korean_version.md §3.2）。
訳は Codex に書かせ、ここでは切り出し・検査・組み立てだけをする。

対象は本番で読まれている3つ:
  corpus_pool_ja.json   → corpus_pool_ko.json   （premium のプール）
  free_pool_ja.json     → free_pool_ko.json     （free のプール）
  free_sentences_ja.json → free_sentences_ko.json（free のバンク）

訳すのは japanese_translation、word_breakdown の meaning / notes、context の
usage_scenarios / cultural_notes / emotion。topic・style・grammatical_role は日本語の
キーのまま残す（配信時に LocalizeContext / LocalizePOS が ko に差し替える）。

ja に後から足された文（pool review の OK）は、既存の ko に無いものだけを切り出すので、
同じ手順を回せば追いつく。

usage:
  # 1. 本番の ja（と既存の ko があればそれも）を作業ディレクトリへ落とす
  python scripts/ko_bank_translate.py fetch --project thai-memo-prod --work $W
  # 2. 未翻訳の文を 100 本ずつのバッチに切る
  python scripts/ko_bank_translate.py prepare --work $W
  # 3. 各バッチを Codex に訳させる（並列数は -j）
  python scripts/ko_bank_translate.py translate --work $W -j 6
  # 4. 検査して ko のファイルを組み立てる（落ちた文は report に出る。3 を再実行すれば訳し直す）
  python scripts/ko_bank_translate.py merge --work $W
  # 5. 目視してから上げる
  python scripts/ko_bank_translate.py upload --project thai-memo-dev --work $W
"""

import argparse
import concurrent.futures
import json
import re
import subprocess
import sys
from pathlib import Path

FILES = ["corpus_pool", "free_pool", "free_sentences"]
CTX_FIELDS = ["usage_scenarios", "cultural_notes", "emotion"]
# 100 本だと Codex が1件ずつ訳さず、スクリプトの定型文で埋めた（2026-10-22）。
BATCH = 40

HANGUL = re.compile(r"[가-힣]")
# 韓国語の欄に混ざってはいけない文字（仮名・漢字・タイ文字）。
FOREIGN = re.compile(r"[぀-ヿ一-鿿฀-๿]")

PROMPT = """タイ語学習アプリ（韓国語話者向け）の例文データの訳を作る。
{inp} の各文（ja=日本語訳、en=英訳（あれば）、words=[タイ語, 日本語の意味, 日本語の補足]、
ctx=日本語の使用場面・文化メモ・感情）を韓国語にして、{out} に JSON 配列で書く。
入力ファイルは書き換えない。{out} 以外のファイルは作らない。

出力の各要素: {{"id": 入力と同じ, "ko": 例文の韓国語訳, "meanings": [words と同じ数・同じ順の韓国語の意味],
"notes": [words と同じ数。日本語の補足が空なら ""], "ctx": {{"usage_scenarios": ..., "cultural_notes": ..., "emotion": ...}}（入力にある項目だけ）}}

進め方（最重要）:
- 訳は1件ずつ自分で読んで書く。スクリプト・辞書・定型文・機械翻訳モデルで訳を作らない。スクリプトは JSON の書き出しと検査にだけ使う
- 同じ型の文（「‘…’라고 말하는 상황에서 쓴다」等）で埋めない。ctx は日本語の内容をそのまま韓国語にする

規則:
- ko はタイ語の文 thai の意味を、韓国語の母語話者が同じ場面で言う自然な一文にする。日本語訳の直訳にしない。thai に無い意味（理由・時制・主語の補足など）を足さない
- 丁寧さは文末の語尾で表す。thai に丁寧の文末詞（ครับ/ค่ะ/คะ 等）があれば 해요체（改まった場面なら 합니다체）、無ければ 반말
- thai に性別・血縁を決める語が無いのに 형/오빠/누나/언니/그녀 を使わない。三人称は 그 사람 など
- 人名・あだ名はハングル。BTS・Grab などラテン文字が正式な固有名はそのまま
- ko は「.」「?」「!」のどれかで終える
- meanings はその文中での意味を1つだけ、短い韓国語で（名詞・動詞は基本形）。「;」や「/」で複数の意味を並べない。文末詞は機能を書く（○ครับ=남성의 공손한 문말 조사）。해요체・반말 という語を meanings に書かない
- notes・ctx は日本語の内容を韓国語にする。日本語・日本人に向けた説明（日本語との比較、カタカナ表記など）は韓国語話者に通じる形に言い換える
- 韓国語の欄に日本語・漢字・タイ文字を入れない（タイ語の語を引用するときだけタイ文字可: notes・ctx）
- 全件を出力する。書き終えたら JSON として読めること、件数、各要素の meanings/notes の数が words と一致することをスクリプトで確かめる
"""


def load(path):
    return json.loads(Path(path).read_text())


def dump(path, data):
    Path(path).write_text(json.dumps(data, ensure_ascii=False, indent=1))


def key(s):
    """ja と ko の文を対応づけるキー。同じタイ語文でも分解が違えば別の文として扱う。"""
    return s["thai_text"] + "\x00" + "|".join(w["word"] for w in s["word_breakdown"])


def cmd_fetch(a):
    work = Path(a.work)
    (work / "src").mkdir(parents=True, exist_ok=True)
    bucket = f"gs://{a.project}-uvm-data"
    for f in FILES:
        for l in ["ja", "en", "ko"]:
            dst = work / "src" / f"{f}_{l}.json"
            r = subprocess.run(["gcloud", "storage", "cp", "-q", f"{bucket}/{f}_{l}.json", str(dst)],
                               capture_output=True, text=True)
            print(f"{f}_{l}: {'ok' if r.returncode == 0 else 'なし'}")


def cmd_prepare(a):
    work = Path(a.work)
    (work / "batches").mkdir(exist_ok=True)
    en_by_thai = {}
    for f in FILES:
        p = work / "src" / f"{f}_en.json"
        if p.exists():
            for s in load(p):
                en_by_thai.setdefault(s["thai_text"], s["japanese_translation"])
    done = set()
    for f in FILES:
        p = work / "src" / f"{f}_ko.json"
        if p.exists():
            done |= {key(s) for s in load(p)}
    # 切り出し済みのバッチは訳し直しも translate が受け持つので、二重に切らない。
    for p in (work / "batches").glob("*.in.json"):
        done |= {x["key"] for x in load(p)}

    todo, seen = [], set()
    for f in FILES:
        for i, s in enumerate(load(work / "src" / f"{f}_ja.json")):
            k = key(s)
            if k in done or k in seen:
                continue
            seen.add(k)
            ctx = s.get("context") or {}
            item = {
                "id": f"{f}:{i}", "key": k, "thai": s["thai_text"], "ja": s["japanese_translation"],
                "words": [[w["word"], w.get("meaning", ""), w.get("notes", "")] for w in s["word_breakdown"]],
                "ctx": {c: ctx[c] for c in CTX_FIELDS if ctx.get(c)},
            }
            if s["thai_text"] in en_by_thai:
                item["en"] = en_by_thai[s["thai_text"]]
            todo.append(item)

    start = len(list((work / "batches").glob("*.in.json")))
    for n in range(0, len(todo), BATCH):
        dump(work / "batches" / f"b{start + n // BATCH:04d}.in.json", todo[n:n + BATCH])
    print(f"未翻訳 {len(todo)} 本 → {(len(todo) + BATCH - 1) // BATCH} バッチ（済み {len(done)}）")


def check(item, out):
    """訳1件を検査し、問題の一覧を返す（空なら合格）。"""
    errs = []
    ko = out.get("ko", "")
    if not HANGUL.search(ko) or FOREIGN.search(ko):
        errs.append("ko")
    if not re.search(r"[.?!]$", ko.strip()):
        errs.append("ko の句点")
    if re.search("해요체|반말", " ".join(out.get("meanings", []))):
        errs.append("meanings に 해요체/반말")
    if any(";" in m for m in out.get("meanings", [])):
        errs.append("meanings に複数の意味")
    n = len(item["words"])
    if len(out.get("meanings", [])) != n or len(out.get("notes", [])) != n:
        errs.append("words の数")
    else:
        for (_, ja_m, ja_n), m, note in zip(item["words"], out["meanings"], out["notes"]):
            if not m.strip() or re.search(r"[぀-ヿ一-鿿]", m):
                errs.append(f"meaning {m!r}")
            if ja_n and re.search(r"[぀-ヿ一-鿿]", note):
                errs.append(f"note {note[:20]!r}")
    for c in item["ctx"]:
        v = (out.get("ctx") or {}).get(c, "")
        if not HANGUL.search(v) or re.search(r"[぀-ヿ一-鿿]", v):
            errs.append(f"ctx.{c}")
        elif c == "usage_scenarios" and "라고 말하는 상황" in v:
            errs.append("ctx.usage_scenarios が定型文")
    return errs


def cmd_translate(a):
    work = Path(a.work)
    batches = sorted((work / "batches").glob("*.in.json"))

    def need(p):
        out = p.with_name(p.name.replace(".in", ".out"))
        if not out.exists():
            return True
        try:
            got = {x["id"]: x for x in load(out)}
        except (json.JSONDecodeError, KeyError, TypeError):
            return True
        return any(x["id"] not in got or check(x, got[x["id"]]) for x in load(p))

    todo = [p for p in batches if need(p)][: a.limit or None]
    print(f"{len(todo)} / {len(batches)} バッチを訳す")

    def run(p):
        out = p.with_name(p.name.replace(".in", ".out"))
        log = p.with_name(p.name.replace(".in.json", ".log"))
        prompt = PROMPT.format(inp=p.name, out=out.name)
        with open(log, "w") as fh:
            r = subprocess.run(
                ["codex", "exec", "--skip-git-repo-check", "--sandbox", "workspace-write", prompt],
                cwd=p.parent, stdin=subprocess.DEVNULL, stdout=fh, stderr=subprocess.STDOUT)
        return p.name, r.returncode, out.exists()

    with concurrent.futures.ThreadPoolExecutor(a.j) as ex:
        for name, rc, ok in ex.map(run, todo):
            print(f"{name}: rc={rc} out={'あり' if ok else 'なし'}", flush=True)


def cmd_merge(a):
    work = Path(a.work)
    good, bad = {}, []
    for p in sorted((work / "batches").glob("*.in.json")):
        out = p.with_name(p.name.replace(".in", ".out"))
        got = {}
        if out.exists():
            try:
                got = {x["id"]: x for x in load(out)}
            except (json.JSONDecodeError, KeyError, TypeError):
                pass
        for item in load(p):
            o = got.get(item["id"])
            errs = ["未出力"] if o is None else check(item, o)
            if errs:
                bad.append({"id": item["id"], "batch": p.name, "thai": item["thai"], "errs": errs})
            else:
                good[item["key"]] = o

    (work / "out").mkdir(exist_ok=True)
    for f in FILES:
        existing = load(work / "src" / f"{f}_ko.json") if (work / "src" / f"{f}_ko.json").exists() else []
        have = {key(s) for s in existing}
        added = []
        for s in load(work / "src" / f"{f}_ja.json"):
            k = key(s)
            if k in have or k not in good:
                continue
            o = good[k]
            s = json.loads(json.dumps(s))
            s["japanese_translation"] = o["ko"]
            for w, m, note in zip(s["word_breakdown"], o["meanings"], o["notes"]):
                w["meaning"] = m
                w["notes"] = note if w.get("notes") else ""
            for c, v in (o.get("ctx") or {}).items():
                if c in CTX_FIELDS and (s.get("context") or {}).get(c):
                    s["context"][c] = v
            have.add(k)
            added.append(s)
        dump(work / "out" / f"{f}_ko.json", existing + added)
        print(f"{f}_ko.json: 既存 {len(existing)} + 追加 {len(added)}")
    dump(work / "report.json", bad)
    print(f"不合格 {len(bad)} 本（report.json。translate を再実行するとそのバッチを訳し直す）")


def cmd_upload(a):
    work = Path(a.work)
    bucket = f"gs://{a.project}-uvm-data"
    for f in FILES:
        src = work / "out" / f"{f}_ko.json"
        subprocess.run(["gcloud", "storage", "cp", str(src), f"{bucket}/{f}_ko.json"], check=True)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    for name in ["fetch", "prepare", "translate", "merge", "upload"]:
        p = sub.add_parser(name)
        p.add_argument("--work", required=True)
        if name in ("fetch", "upload"):
            p.add_argument("--project", required=True)
        if name == "translate":
            p.add_argument("-j", type=int, default=4)
            p.add_argument("--limit", type=int, default=0, help="訳すバッチ数の上限（試し用）")
    a = ap.parse_args()
    globals()[f"cmd_{a.cmd}"](a)


if __name__ == "__main__":
    sys.exit(main())
