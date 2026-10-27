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
    # プロンプトで禁じている形。cmd_qa と同じ規則で、ここで落として訳し直させる。
    if POLITE_TH.search(item["thai"]) and not POLITE_KO.search(ko.strip()):
        errs.append("丁寧なのにため口")
    if CASUAL_TH.search(item["thai"]) and not POLITE_TH.search(item["thai"]) and POLITE_KO.search(ko.strip()):
        errs.append("ため口なのに敬語")
    if KIN_KO.search(ko) and not KIN_TH.search(item["thai"]):
        errs.append("性別・血縁の決めつけ")
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


GEMINI_RULES = PROMPT.split("規則:\n", 1)[1].rsplit("- 全件を出力する", 1)[0]

GEMINI_SCHEMA = {
    "type": "array",
    "items": {
        "type": "object",
        "properties": {
            "id": {"type": "string"},
            "ko": {"type": "string"},
            "meanings": {"type": "array", "items": {"type": "string"}},
            "notes": {"type": "array", "items": {"type": "string"}},
            "ctx": {
                "type": "object",
                "properties": {c: {"type": "string"} for c in CTX_FIELDS},
                # 必須にしないと flash-lite は usage_scenarios 以外を落とす。入力に無い項目は "" で返り、
                # merge は元の文にある項目だけを使う。
                "required": CTX_FIELDS,
            },
        },
        "required": ["id", "ko", "meanings", "notes", "ctx"],
    },
}


def _write_body(body):
    """リクエスト本文を一時ファイルに書いてパスを返す（curl に渡す）。"""
    import tempfile

    with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as fh:
        json.dump(body, fh, ensure_ascii=False)
    return fh.name


def gemini_translate(items, model, api_key):
    """items を1リクエストで訳す。戻り値は (訳の配列, usageMetadata)。"""
    prompt = (
        "タイ語学習アプリ（韓国語話者向け）の例文データの訳を作る。各文（thai=タイ語、ja=日本語訳、"
        "en=英訳（あれば）、words=[タイ語, 日本語の意味, 日本語の補足]、ctx=日本語の使用場面・文化メモ・感情）を"
        "韓国語にする。各要素の meanings・notes は words と同じ数・同じ順。日本語の補足が空なら notes は \"\"。"
        "ctx は入力にある項目だけ。\n\n規則:\n" + GEMINI_RULES +
        "\n入力:\n" + json.dumps([{k: v for k, v in x.items() if k != "key"} for x in items], ensure_ascii=False)
    )
    body = {
        "contents": [{"role": "user", "parts": [{"text": prompt}]}],
        # 上限なしだと1リクエストの出力が暴走して $1 かかった（2026-10-22）。10本の訳は通常 8k トークン前後。
        "generationConfig": {"responseMimeType": "application/json", "responseSchema": GEMINI_SCHEMA,
                             "maxOutputTokens": 16000,
                             # 暴走は thinking 側で起きる（思考トークンは maxOutputTokens の外で課金される）。
                             "thinkingConfig": {"thinkingBudget": 0}},
    }
    # macOS の python.org 版は証明書が入っていないことがあるので curl で送る。
    # キーはヘッダーで渡す（URL に載せるとプロセス一覧に出る）。
    r = subprocess.run(
        ["curl", "-sS", "--max-time", "300", "-H", "Content-Type: application/json",
         "-H", "@-", "--data-binary", "@" + _write_body(body),
         f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent"],
        input=f"x-goog-api-key: {api_key}\n", capture_output=True, text=True, check=True)
    res = json.loads(r.stdout)
    if "error" in res:
        raise RuntimeError(res["error"].get("message"))
    text = res["candidates"][0]["content"]["parts"][-1]["text"]
    return json.loads(text), res.get("usageMetadata", {})


# 100万トークンあたりの単価（USD）。flash-lite は internal/gemini/quiz.go と同じ値。
GEMINI_PRICE = {"gemini-3.1-flash-lite": (0.25, 1.50), "gemini-3.8-flash": (0.75, 3.75)}


def outputs(p):
    """バッチ p の訳を、検査に通ったものだけ id → 訳で返す。Codex の訳を優先し、無ければ Gemini。"""
    items = {x["id"]: x for x in load(p)}
    good = {}
    for out in [p.with_name(p.name.replace(".in", ".out"))] + sorted(p.parent.glob(p.name.replace(".in.json", ".gemini-*.json"))):
        if not out.exists():
            continue
        try:
            got = load(out)
        except json.JSONDecodeError:
            continue
        for o in got if isinstance(got, list) else []:
            i = o.get("id") if isinstance(o, dict) else None
            if i in items and i not in good and not check(items[i], o):
                good[i] = o
    return good


def cmd_gemini(a):
    """Codex で訳せていない文を Gemini で訳す（出力は batches/*.gemini-<model>.json）。

    バッチごとに累計の費用を出し、--budget（USD）を超えたら新しいバッチを始めない。
    """
    work = Path(a.work)
    key_ = subprocess.run(
        ["gcloud", "secrets", "versions", "access", "latest", "--secret", "gemini-api-key",
         "--project", a.project], capture_output=True, text=True, check=True).stdout.strip()
    price_in, price_out = GEMINI_PRICE[a.model]
    batches = [p for p in sorted((work / "batches").glob("*.in.json"))
               if len(outputs(p)) < len(load(p))][: a.limit or None]
    print(f"{len(batches)} バッチを訳す", flush=True)
    lock = __import__("threading").Lock()
    spent = {"usd": 0.0, "in": 0, "out": 0}

    def run(p):
        if spent["usd"] >= a.budget:
            return p.name, None
        done = outputs(p)
        items = [x for x in load(p) if x["id"] not in done]
        dst = p.with_name(p.name.replace(".in.json", f".gemini-{a.model}.json"))
        outs = load(dst) if dst.exists() else []
        for n in range(0, len(items), a.per_request):
            for attempt in range(3):
                try:
                    out, usage = gemini_translate(items[n:n + a.per_request], a.model, key_)
                    break
                except Exception as e:  # noqa: BLE001 再試行して最後は諦める
                    out, usage = [], {}
                    if attempt == 2:
                        print(f"{p.name}[{n}]: {e}", flush=True)
            # 前回の訳より新しい訳を先に置く（outputs は先に見つけた合格の訳を使う）。
            outs = out + outs
            with lock:
                t_in = usage.get("promptTokenCount", 0)
                t_out = usage.get("candidatesTokenCount", 0) + usage.get("thoughtsTokenCount", 0)
                spent["in"] += t_in
                spent["out"] += t_out
                cost = (t_in * price_in + t_out * price_out) / 1e6
                spent["usd"] += cost
                if cost > 0.05:
                    print(f"{p.name}[{n}]: 1リクエスト ${cost:.3f} {usage}", flush=True)
        dump(dst, outs)
        return p.name, len(outputs(p))

    with concurrent.futures.ThreadPoolExecutor(a.j) as ex:
        for name, n in ex.map(run, batches):
            if n is None:
                print(f"{name}: 予算 ${a.budget} に達したので飛ばした", flush=True)
            else:
                print(f"{name}: 合格 {n} 本 / 累計 ${spent['usd']:.3f}", flush=True)
    print(f"費用 ${spent['usd']:.3f}（入力 {spent['in']} / 出力 {spent['out']} トークン）")


# 祭りの名前の表記を app_ko.arb・constants_data_ko.go にそろえる（訳では3通りに揺れた）。
SPELLING = {"송크란": "송끄란", "쏭끄란": "송끄란", "로이끄라통": "러이끄라통", "로이크라통": "러이끄라통"}


def normalize(text):
    for a, b in SPELLING.items():
        text = text.replace(a, b)
    return text


def load_fixes(work):
    """目視の修正（work/fixes.json）。{id: {"ko": 部分, "ja": 部分, "drop": bool}}。

    部分は {"ko" または "japanese_translation": 訳, "meanings": {語の番号: 意味}, "notes": {番号: 補足},
    "ctx": {項目: 値}}。drop は ko に入れない（タイ語自体がおかしい文など）。
    """
    p = work / "fixes.json"
    return load(p) if p.exists() else {}


def apply_fix(o, part):
    """訳 o（ko の訳か ja の文）に部分の修正を当てたコピーを返す。"""
    o = json.loads(json.dumps(o))
    for f in ("ko", "japanese_translation"):
        if f in part:
            o[f] = part[f]
    if "word_breakdown" in o:  # ja の文
        for n, v in part.get("meanings", {}).items():
            o["word_breakdown"][int(n)]["meaning"] = v
        for n, v in part.get("notes", {}).items():
            o["word_breakdown"][int(n)]["notes"] = v
        o.setdefault("context", {}).update(part.get("ctx", {}))
    else:
        for n, v in part.get("meanings", {}).items():
            o["meanings"][int(n)] = v
        for n, v in part.get("notes", {}).items():
            o["notes"][int(n)] = v
        o.setdefault("ctx", {}).update(part.get("ctx", {}))
    return o


def cmd_jafix(a):
    """fixes.json の ja の修正を本番の ja のファイルに当てる（取り直し→バックアップ→上げる）。

    pool review で文が足されていてもよいように、ファイルは毎回取り直して文のキーで当てる。
    """
    work = Path(a.work)
    fixes = {i: f["ja"] for i, f in load_fixes(work).items() if f.get("ja")}
    items = {x["id"]: x for p in (work / "batches").glob("*.in.json") for x in load(p)}
    bucket = f"gs://{a.project}-uvm-data"
    stamp = __import__("datetime").date.today().strftime("%Y%m%d")
    for f in FILES:
        mine = {items[i]["key"]: fx for i, fx in fixes.items() if i.startswith(f + ":")}
        if not mine:
            continue
        cur = work / "src" / f"{f}_ja.current.json"
        subprocess.run(["gcloud", "storage", "cp", "-q", f"{bucket}/{f}_ja.json", str(cur)], check=True)
        data = load(cur)
        hit = 0
        for n, s in enumerate(data):
            if key(s) in mine:
                data[n] = apply_fix(s, mine[key(s)])
                hit += 1
        print(f"{f}_ja.json: 修正 {hit} / {len(mine)} 本")
        if not a.write:
            continue
        subprocess.run(["gcloud", "storage", "cp", "-q", f"{bucket}/{f}_ja.json",
                        f"{bucket}/{f}_ja.json.bak-{stamp}-kofix"], check=True)
        dump(cur, data)
        subprocess.run(["gcloud", "storage", "cp", "-q", str(cur), f"{bucket}/{f}_ja.json"], check=True)
    if not a.write:
        print("dry run（--write で上げる）")


def cmd_merge(a):
    work = Path(a.work)
    good, bad = {}, []
    for p in sorted((work / "batches").glob("*.in.json")):
        got = outputs(p)
        for item in load(p):
            if item["id"] in got:
                good[item["key"]] = got[item["id"]]
            else:
                bad.append({"id": item["id"], "batch": p.name, "thai": item["thai"]})
    key_of = {x["id"]: x["key"] for p in (work / "batches").glob("*.in.json") for x in load(p)}
    for i, fix in load_fixes(work).items():
        k = key_of[i]
        if fix.get("drop"):
            good.pop(k, None)
        elif k in good:
            good[k] = apply_fix(good[k], fix.get("ko", {}))

    (work / "out").mkdir(exist_ok=True)
    for f in FILES:
        existing = load(work / "src" / f"{f}_ko.json") if (work / "src" / f"{f}_ko.json").exists() else []
        have = {key(s) for s in existing}
        added = []
        for s in load(work / "src" / f"{f}_ja.json"):
            k = key(s)
            if k in have or k not in good:
                continue
            o = json.loads(normalize(json.dumps(good[k], ensure_ascii=False)))
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
    print(f"不合格 {len(bad)} 本（report.json。translate / gemini を再実行すると訳し直す）")


# 文末詞は語の一部（เขา の ขา、เจ้าของ の จ้า）と区別するため、句の終わりにあるものだけ数える。
_END = r"(?=$|\s|[?!.,ๆ])"
POLITE_TH = re.compile(r"(ครับ|คับ|ค่ะ|คะ|(?<!เ)ขา|ขอรับ|นะคะ)" + _END)
CASUAL_TH = re.compile(r"มึง|(?<![\u0e01-\u0e4e])กู(?![\u0e01-\u0e4e])|(ว่ะ|วะ|เว้ย|จ้ะ|จ้า|เนอะ)" + _END)
POLITE_KO = re.compile(r"(요|니다|니까|세요|십시오|죠)[.?!…~]*$")
# 형 は 인형・형태 などの一部と区別するため、単独の呼びかけ・名前の後ろだけ数える。
KIN_KO = re.compile(r"오빠|누나|언니|그녀|(?<![가-힣])형(?=$|[\s,.!?]|님|이|아|은|도|한테|에게)")
KIN_TH = re.compile(r"พี่ชาย|พี่สาว|น้องชาย|น้องสาว|ผู้หญิง|ผู้ชาย|ลูกสาว|ลูกชาย|สาว|หนุ่ม|เฮีย|เจ๊")
JA_LEFT = re.compile(r"일본어|일본인|가타카나|히라가나|한자")


def cmd_qa(a):
    """検査に通った訳を、規則で拾える品質の問題で洗う（全件）。抜き取りの目視とは別。"""
    work = Path(a.work)
    hits = {k: [] for k in ["丁寧なのにため口", "ため口なのに敬語", "性別・血縁の決めつけ", "日本語向けの説明", "長さの極端な差"]}
    total = 0
    for p in sorted((work / "batches").glob("*.in.json")):
        items = {x["id"]: x for x in load(p)}
        for i, o in outputs(p).items():
            it, ko = items[i], o["ko"].strip()
            total += 1
            row = {"id": i, "thai": it["thai"], "ja": it["ja"], "ko": ko}
            if POLITE_TH.search(it["thai"]) and not POLITE_KO.search(ko):
                hits["丁寧なのにため口"].append(row)
            if CASUAL_TH.search(it["thai"]) and not POLITE_TH.search(it["thai"]) and POLITE_KO.search(ko):
                hits["ため口なのに敬語"].append(row)
            if KIN_KO.search(ko) and not KIN_TH.search(it["thai"]):
                hits["性別・血縁の決めつけ"].append(row)
            if JA_LEFT.search(" ".join(o["notes"]) + " ".join((o.get("ctx") or {}).values())):
                hits["日本語向けの説明"].append(row)
            r = len(ko) / max(len(it["ja"]), 1)
            if r < 0.4 or r > 2.5:
                hits["長さの極端な差"].append(row)
    dump(work / "qa.json", hits)
    print(f"検査済み {total} 本")
    for k, v in hits.items():
        print(f"  {k}: {len(v)} 本（{100 * len(v) / max(total, 1):.1f}%）")
    print("一覧は qa.json")


def cmd_upload(a):
    work = Path(a.work)
    bucket = f"gs://{a.project}-uvm-data"
    for f in FILES:
        src = work / "out" / f"{f}_ko.json"
        subprocess.run(["gcloud", "storage", "cp", str(src), f"{bucket}/{f}_ko.json"], check=True)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    for name in ["fetch", "prepare", "translate", "merge", "qa", "upload"]:
        p = sub.add_parser(name)
        p.add_argument("--work", required=True)
        if name in ("fetch", "upload"):
            p.add_argument("--project", required=True)
        if name == "translate":
            p.add_argument("-j", type=int, default=4)
            p.add_argument("--limit", type=int, default=0, help="訳すバッチ数の上限（試し用）")
    j = sub.add_parser("jafix")
    j.add_argument("--work", required=True)
    j.add_argument("--project", required=True)
    j.add_argument("--write", action="store_true")
    g = sub.add_parser("gemini")
    g.add_argument("--work", required=True)
    g.add_argument("--project", default="thai-memo-dev", help="gemini-api-key を読む GCP プロジェクト")
    g.add_argument("--model", default="gemini-3.1-flash-lite")
    g.add_argument("--limit", type=int, default=0, help="訳すバッチ数の上限（0 は全部）")
    g.add_argument("--budget", type=float, default=1.0, help="この費用（USD）に達したら止める")
    g.add_argument("--per-request", type=int, default=10, help="1リクエストに入れる文の数")
    g.add_argument("-j", type=int, default=4)
    a = ap.parse_args()
    globals()[f"cmd_{a.cmd}"](a)


if __name__ == "__main__":
    sys.exit(main())
