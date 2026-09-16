"""語彙テストの出題語（GCS vocab_test_items_<lang>.json）を作る。

オンボーディング末尾と設定画面の語彙テストは、この JSON の語を 4 択で出す
（functions/go/internal/uvm/vocabtest_items.go）。誤答の選択肢も同じ段の語の
訳から作るので、1 語 1 訳（短い名詞・動詞句）に絞ること。

段の定義は uvm.TestStages と揃える。ずれると測定値がずれる。

1 段あたり TestItemsPerStage(6) 問を出し、誤答も同じ段から引くので、段ごとに
最低でも 10 語、余裕を見て 20 語は残ること。生成後に段ごとの語数を必ず数える
（高ランク帯ほど訳の重複と skip で目減りする）。

--lang に複数を渡すと 1 回で全言語ぶんを作り、出題語を言語間で揃える。
言語ごとに走らせると skip 判定と訳の重複除去がずれて、同じ学習者でも
言語で測定値が変わる。必ずまとめて生成すること。

--from-ja は既存の ja を正として、他言語の訳だけを埋める。出題語と rank を
1 語も動かさないので、配信中に英語版だけ追いつかせたいときはこちら
（--lang ja,en で作り直すと ja の出題語も入れ替わり、既存ユーザーの
スコアの出発点が変わる）。

usage:
  GEMINI_API_KEY=... python scripts/build_vocab_test_items.py \
      --lang ja,en --per-stage 20 --out scripts/bank_out
  # ja はそのままで en だけ埋める
  GEMINI_API_KEY=... python scripts/build_vocab_test_items.py \
      --from-ja --lang ja,en --out scripts/bank_out
  # 目視で確認してから
  GCLOUD_PROJECT=thai-memo-prod python scripts/build_vocab_test_items.py \
      --upload-only --lang ja,en --out scripts/bank_out
"""

import argparse
import json
import os
import random
import re
import sys
import urllib.request
from pathlib import Path

# ローカル実行では CA バンドルの明示が要る。
try:
    import certifi

    os.environ.setdefault("SSL_CERT_FILE", certifi.where())
except ImportError:
    pass

# functions/go/internal/uvm/vocabtest.go の TestStages と同じ並び。
STAGES = [
    (1, 50),
    (51, 150),
    (151, 300),
    (301, 450),
    (451, 600),
    (601, 900),
    (901, 1200),
    (1201, 1600),
    (1601, 2100),
    (2101, 2600),
    (2601, 3000),
]

FREQ_RANK_PATH = Path(__file__).parent / "corpus" / "freq_rank_top10000.json"

# gemini-2.5 系は新規APIキーから使えない（internal/gemini/quiz.go と同じ理由）。
MODEL = os.environ.get("VOCAB_TEST_MODEL", "gemini-3.1-flash-lite")
ENDPOINT = (
    "https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent"
)

LANG_NAME = {"ja": "日本語", "en": "English"}

PROMPT = """\
次のタイ語の単語それぞれに、{lang_name}の訳を1つだけ付けてください。

条件:
- 訳は名詞または動詞の短い句（最大8文字程度）。説明文にしない
- 単独では意味が立たない語（接辞・助詞・数詞の一部・固有名詞）は skip: true
- 同じ訳を2つ以上の語に付けない（4択の誤答に使うため）

JSON配列だけを返す。形式:
[{{"word": "...", "gloss": "...", "skip": false}}]

単語:
{words}
"""


PROMPT_FILL = """\
次のタイ語の単語それぞれに、{lang_name}の訳を1つだけ付けてください。

条件:
- 訳は名詞または動詞の短い句（最大8文字程度）。説明文にしない
- どの語にも必ず訳を付ける（skip しない）。単独で意味が立たない語（助詞・接辞）は
  働きがわかる短い語にする
- 同じ訳を2つ以上の語に付けない
{avoid}
JSON配列だけを返す。形式:
[{{"word": "...", "gloss": "..."}}]

単語:
{words}
"""


def load_freq_rank() -> dict[str, int]:
    with FREQ_RANK_PATH.open(encoding="utf-8") as f:
        return json.load(f)


def sample_words(freq_rank: dict[str, int], per_stage: int, seed: int) -> list[tuple[str, int]]:
    """段ごとに候補語を抽出する。key_word と同じく2文字以上に限る。"""
    rnd = random.Random(seed)
    picked: list[tuple[str, int]] = []
    for low, high in STAGES:
        band = [
            (w, r) for w, r in freq_rank.items() if low <= r <= high and len(w) >= 2
        ]
        band.sort(key=lambda x: x[1])
        # 訳が付かない語で目減りするので多めに引く。
        take = min(len(band), per_stage * 2)
        picked.extend(rnd.sample(band, take))
    return picked


def ask_gloss(
    words: list[str], lang: str, api_key: str,
    template: str = PROMPT, avoid: str = "",
) -> list[dict]:
    text = template.format(
        lang_name=LANG_NAME[lang], words="\n".join(words), avoid=avoid
    ) if "{avoid}" in template else template.format(
        lang_name=LANG_NAME[lang], words="\n".join(words)
    )
    body = json.dumps(
        {
            "contents": [{"parts": [{"text": text}]}],
            "generationConfig": {"temperature": 0, "responseMimeType": "application/json"},
        }
    ).encode()
    req = urllib.request.Request(
        ENDPOINT.format(model=MODEL),
        data=body,
        headers={"Content-Type": "application/json", "x-goog-api-key": api_key},
    )
    with urllib.request.urlopen(req, timeout=120) as res:
        payload = json.load(res)
    text = payload["candidates"][0]["content"]["parts"][0]["text"]
    # responseMimeType を無視してコードフェンスを付けてくることがある。
    text = re.sub(r"^```(?:json)?|```$", "", text.strip(), flags=re.MULTILINE).strip()
    return json.loads(text)


def build_all(langs: list[str], per_stage: int, seed: int, api_key: str) -> dict[str, list[dict]]:
    """全言語ぶんをまとめて作る。出題語は言語をまたいで同一にする。

    言語ごとに別々に作ると、skip 判定と訳の重複除去が呼び出しごとに揺れて
    日英で出題語がずれる（ja 404 / en 393、1-50 帯は 34 / 23 だった）。
    段は頻度ランクの帯なので、語が違えば同じ学習者でも測定値が変わる。
    どれか 1 言語で落ちた語は全言語から落として、語の集合を揃える。
    """
    freq_rank = load_freq_rank()
    rank_of = dict(sample_words(freq_rank, per_stage, seed))
    words = list(rank_of)

    glosses: dict[str, dict[str, str]] = {lang: {} for lang in langs}
    for lang in langs:
        for i in range(0, len(words), 40):
            chunk = words[i : i + 40]
            for entry in ask_gloss(chunk, lang, api_key):
                word = entry.get("word", "")
                gloss = (entry.get("gloss") or "").strip()
                if entry.get("skip") or not gloss or word not in rank_of:
                    continue
                glosses[lang][word] = gloss
            print(f"  {lang}: {min(i + 40, len(words))}/{len(words)}", file=sys.stderr)

    # 訳が重なると 4 択の選択肢が潰れる。誤答は同じ段からしか引かない
    # （uvm.BuildStageQuestions）ので、重複を見るのも段の中だけでよい。
    # 全段まとめて見ると、別の帯の語と訳がぶつかっただけで落ちる。
    dropped: set[str] = set()
    for lang in langs:
        missing = [w for w in words if w not in glosses[lang]]
        dropped.update(missing)
        for low, high in STAGES:
            seen: set[str] = set()
            for word in sorted(
                (w for w in words if low <= rank_of[w] <= high), key=lambda w: rank_of[w]
            ):
                gloss = glosses[lang].get(word)
                if gloss is None:
                    continue
                if gloss in seen:
                    dropped.add(word)
                    continue
                seen.add(gloss)

    out: dict[str, list[dict]] = {}
    for lang in langs:
        items = [
            {"word": w, "rank": rank_of[w], "gloss": glosses[lang][w]}
            for w in words
            if w not in dropped
        ]
        items.sort(key=lambda x: x["rank"])
        out[lang] = items

    first = [it["word"] for it in out[langs[0]]]
    for lang in langs[1:]:
        assert [it["word"] for it in out[lang]] == first, f"{lang} の出題語がずれた"

    for low, high in STAGES:
        n = sum(1 for it in out[langs[0]] if low <= it["rank"] <= high)
        mark = "" if n >= per_stage else "  ← 不足"
        print(f"  段 [{low},{high}]: {n} 語{mark}", file=sys.stderr)
    return out


def build_from_ja(
    langs: list[str], out_dir: Path, api_key: str
) -> dict[str, list[dict]]:
    """既存の ja を正として、他言語の訳だけを埋める。

    出題語と rank は ja のファイルから1語も動かさない。段は頻度ランクの帯なので、
    語が入れ替わると同じ学習者でも測定値が変わる。ja を作り直さずに英語版だけ
    追いつかせたいとき（言語を後から足したとき）はこちらを使う。

    すでに訳がある語はその訳を残す。足りない語だけ LLM に聞き、段の中で訳が
    重なったぶんは「使用済みの訳」を渡して付け直させる。語は落とさない
    （落とすと ja とずれる）。
    """
    ja_path = out_dir / "vocab_test_items_ja.json"
    if not ja_path.exists():
        raise SystemExit(f"{ja_path} が要ります（ja が正）")
    ja_items = json.loads(ja_path.read_text(encoding="utf-8"))
    words = [it["word"] for it in ja_items]
    rank_of = {it["word"]: it["rank"] for it in ja_items}

    out: dict[str, list[dict]] = {"ja": ja_items}
    for lang in langs:
        if lang == "ja":
            continue
        path = out_dir / f"vocab_test_items_{lang}.json"
        gloss: dict[str, str] = {}
        if path.exists():
            for it in json.loads(path.read_text(encoding="utf-8")):
                gloss[it["word"]] = it["gloss"]
        missing = [w for w in words if w not in gloss]
        print(f"  {lang}: 既存 {len(words) - len(missing)} 語 / 追加 {len(missing)} 語",
              file=sys.stderr)
        for i in range(0, len(missing), 40):
            chunk = missing[i : i + 40]
            for entry in ask_gloss(chunk, lang, api_key, PROMPT_FILL):
                word = entry.get("word", "")
                g = (entry.get("gloss") or "").strip()
                if g and word in rank_of:
                    gloss[word] = g

        # 段の中の重複だけ付け直す。誤答は同じ段からしか引かない。
        for _ in range(2):
            dup: list[str] = []
            for low, high in STAGES:
                seen: dict[str, str] = {}
                for w in sorted(
                    (w for w in words if low <= rank_of[w] <= high), key=lambda w: rank_of[w]
                ):
                    g = gloss.get(w)
                    if g is None:
                        dup.append(w)
                        continue
                    if g.lower() in seen:
                        dup.append(w)
                        continue
                    seen[g.lower()] = w
            if not dup:
                break
            taken = sorted({g for g in gloss.values()})
            avoid = "- 次の訳はすでに使われている。使わないこと: " + " / ".join(taken) + "\n"
            print(f"  {lang}: 訳が重なった {len(dup)} 語を付け直す", file=sys.stderr)
            for i in range(0, len(dup), 40):
                for entry in ask_gloss(dup[i : i + 40], lang, api_key, PROMPT_FILL, avoid):
                    word = entry.get("word", "")
                    g = (entry.get("gloss") or "").strip()
                    if g and word in rank_of:
                        gloss[word] = g

        blank = [w for w in words if not gloss.get(w)]
        if blank:
            raise SystemExit(f"{lang}: 訳が付かなかった語がある: {blank[:10]}")
        out[lang] = [
            {"word": w, "rank": rank_of[w], "gloss": gloss[w]} for w in words
        ]
        assert [it["word"] for it in out[lang]] == words, f"{lang} の出題語がずれた"
    return out


def upload(project_id: str, lang: str, path: Path) -> None:
    from google.cloud import storage

    name = f"vocab_test_items_{lang}.json"
    blob = storage.Client(project=project_id).bucket(f"{project_id}-uvm-data").blob(name)
    blob.upload_from_filename(str(path), content_type="application/json")
    print(f"uploaded → gs://{project_id}-uvm-data/{name}")


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--lang", default="ja", help="カンマ区切り（ja,en）")
    p.add_argument("--per-stage", type=int, default=20, help="1段あたりの目標語数")
    p.add_argument("--seed", type=int, default=20260903)
    p.add_argument("--out", default="scripts/bank_out")
    p.add_argument("--upload", action="store_true", help="生成後にGCSへ上げる")
    p.add_argument("--upload-only", action="store_true", help="生成済みJSONを上げるだけ")
    p.add_argument(
        "--from-ja",
        action="store_true",
        help="既存の ja を正として他言語の訳だけ埋める（出題語と rank を変えない）",
    )
    a = p.parse_args()

    out_dir = Path(a.out)
    out_dir.mkdir(parents=True, exist_ok=True)
    project_id = os.environ.get("GCLOUD_PROJECT", "")

    langs = [x.strip() for x in a.lang.split(",") if x.strip()]
    for lang in langs:
        if lang not in LANG_NAME:
            raise SystemExit(f"未対応の言語: {lang}")

    if a.upload_only:
        for lang in langs:
            upload(project_id, lang, out_dir / f"vocab_test_items_{lang}.json")
        return

    api_key = os.environ.get("GEMINI_API_KEY", "")
    if not api_key:
        raise SystemExit("GEMINI_API_KEY が要ります")
    print(f"{','.join(langs)}: 生成中", file=sys.stderr)
    if a.from_ja:
        built = build_from_ja(langs, out_dir, api_key)
    else:
        built = build_all(langs, a.per_stage, a.seed, api_key)
    for lang in langs:
        path = out_dir / f"vocab_test_items_{lang}.json"
        path.write_text(
            json.dumps(built[lang], ensure_ascii=False, indent=2), encoding="utf-8"
        )
        print(f"{lang}: {len(built[lang])} 語 → {path}", file=sys.stderr)
        if a.upload:
            upload(project_id, lang, path)


if __name__ == "__main__":
    main()
