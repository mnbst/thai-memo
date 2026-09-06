"""語彙テストの出題語（GCS vocab_test_items_<lang>.json）を作る。

オンボーディング末尾と設定画面の語彙テストは、この JSON の語を 4 択で出す
（functions/go/internal/uvm/vocabtest_items.go）。誤答の選択肢も同じ段の語の
訳から作るので、1 語 1 訳（短い名詞・動詞句）に絞ること。

段の定義は uvm.TestStages と揃える。ずれると測定値がずれる。

1 段あたり TestItemsPerStage(6) 問を出し、誤答も同じ段から引くので、段ごとに
最低でも 10 語、余裕を見て 20 語は残ること。生成後に段ごとの語数を必ず数える
（高ランク帯ほど訳の重複と skip で目減りする）。

usage:
  GEMINI_API_KEY=... python scripts/build_vocab_test_items.py \
      --lang ja,en --per-stage 20 --out scripts/bank_out
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

# ローカル実行では CA バンドルの明示が要る（build_free_sentence_bank.py と同じ）。
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


def ask_gloss(words: list[str], lang: str, api_key: str) -> list[dict]:
    body = json.dumps(
        {
            "contents": [
                {
                    "parts": [
                        {
                            "text": PROMPT.format(
                                lang_name=LANG_NAME[lang],
                                words="\n".join(words),
                            )
                        }
                    ]
                }
            ],
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


def build(lang: str, per_stage: int, seed: int, api_key: str) -> list[dict]:
    freq_rank = load_freq_rank()
    rank_of = dict(sample_words(freq_rank, per_stage, seed))

    glosses: dict[str, str] = {}
    words = list(rank_of)
    for i in range(0, len(words), 40):
        chunk = words[i : i + 40]
        for entry in ask_gloss(chunk, lang, api_key):
            word = entry.get("word", "")
            gloss = (entry.get("gloss") or "").strip()
            if entry.get("skip") or not gloss or word not in rank_of:
                continue
            glosses[word] = gloss
        print(f"  {lang}: {min(i + 40, len(words))}/{len(words)}", file=sys.stderr)

    # 訳が重なると 4 択の選択肢が潰れる。先に出た語を残す。
    seen: set[str] = set()
    items: list[dict] = []
    for word, gloss in glosses.items():
        if gloss in seen:
            continue
        seen.add(gloss)
        items.append({"word": word, "rank": rank_of[word], "gloss": gloss})
    items.sort(key=lambda x: x["rank"])

    for low, high in STAGES:
        n = sum(1 for it in items if low <= it["rank"] <= high)
        mark = "" if n >= per_stage else "  ← 不足"
        print(f"  段 [{low},{high}]: {n} 語{mark}", file=sys.stderr)
    return items


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
    a = p.parse_args()

    out_dir = Path(a.out)
    out_dir.mkdir(parents=True, exist_ok=True)
    project_id = os.environ.get("GCLOUD_PROJECT", "")

    for lang in a.lang.split(","):
        lang = lang.strip()
        if lang not in LANG_NAME:
            raise SystemExit(f"未対応の言語: {lang}")
        path = out_dir / f"vocab_test_items_{lang}.json"

        if a.upload_only:
            upload(project_id, lang, path)
            continue

        api_key = os.environ.get("GEMINI_API_KEY", "")
        if not api_key:
            raise SystemExit("GEMINI_API_KEY が要ります")
        print(f"{lang}: 生成中", file=sys.stderr)
        items = build(lang, a.per_stage, a.seed, api_key)
        path.write_text(
            json.dumps(items, ensure_ascii=False, indent=2), encoding="utf-8"
        )
        print(f"{lang}: {len(items)} 語 → {path}", file=sys.stderr)
        if a.upload:
            upload(project_id, lang, path)


if __name__ == "__main__":
    main()
