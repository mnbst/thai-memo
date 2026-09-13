#!/usr/bin/env python3
"""静的コーパスを例文バンク（GCS）の形へ書き出す。

cmd/translate が出した corpus.jsonl を、Cloud Functions の
internal/sentence.Sentence がそのまま読める JSON 配列にする。
一文二訳なので言語ごとに1ファイルへ割る。タイ語本文・発音・音節は
どちらのファイルにも同じものが入る（訳と語義だけが入れ替わる）。

    python3 scripts/export_corpus_bank.py \
        --in scripts/corpus/corpus.jsonl --out-dir scripts/corpus/bank

    gsutil cp scripts/corpus/bank/corpus_sentences_*.json \
        gs://<project>-uvm-data/

word_denylist.json の語は pack_corpus.py と同じくここでも落とす。
生成後に見つかった語をリストへ足せば、詰め直すだけで消える。
"""

import argparse
import json
import os
from collections import OrderedDict

LANGS = ("ja", "en")


def load_denylist(path):
    """除外語の集合。`_` 始まりのキーは説明文なので読み飛ばす。"""
    if not os.path.exists(path):
        return set()
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    return {
        word
        for key, category in data.items()
        if not key.startswith("_")
        for word in category["words"]
    }


def load_usage(path):
    """cmd/usagefill のサイドカーを thai_text で索く形にする。

    無ければ空。使い方の項目が無くてもバンクは作れる（アプリ側は
    context に無いキーを出さないだけ）。
    """
    usage = {}
    if not path or not os.path.exists(path):
        return usage
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            row = json.loads(line)
            if row.get("error") or not row.get("thai_text"):
                continue
            usage[row["thai_text"]] = row
    return usage


def usage_context(row, lang):
    """使い方の4項目を、その言語の値で返す。

    style だけは日本語ラベルのまま入れる。en 配信では
    sentence.LocalizeContext が styleLabelsEN で英語へ差し替えるので、
    ここで英訳すると未知の値になって差し替えが効かない。
    emotion / usage_scenarios / cultural_notes は自由記述なので
    言語ごとの文をそのまま入れる。
    """
    if not row:
        return {}
    suffix = "ja" if lang == "ja" else "en"
    out = OrderedDict()
    if row.get("style"):
        out["style"] = row["style"]
    for key, field in (
        ("emotion", "emotion"),
        ("usage_scenarios", "usage"),
        ("cultural_notes", "culture"),
    ):
        value = row.get(f"{field}_{suffix}")
        if value:
            out[key] = value
    return out


def to_sentence(row, lang, usage=None):
    """コーパスの1行を internal/sentence.Sentence の JSON へ落とす。

    対象語の語義説明（note）はその語の word_breakdown に入れる。LLM 生成では
    target_notes を展開して同じ場所へ入るので、受け取り側は経路を区別しない。
    """
    target = row["target_word"]
    note = row.get(f"note_{lang}") or ""
    words = []
    for word in row.get("words", []):
        words.append(
            OrderedDict(
                word=word["word"],
                meaning=word.get(lang, ""),
                notes=note if word["word"] == target else "",
                syllables=word.get("syllables") or [],
                pronunciation=word.get("pronunciation", ""),
                grammatical_role=word.get("grammatical_role", ""),
            )
        )
    return OrderedDict(
        thai_text=row["thai_text"],
        pronunciation=row.get("pronunciation", ""),
        japanese_translation=row[lang],
        word_breakdown=words,
        context=OrderedDict(
            topic=row["topic"],
            subTheme=row.get("sub_theme") or "",
            **usage_context(usage, lang),
        ),
        key_word=target,
        key_word_rank=row["key_word_rank"],
        # バンクの項目は premium 仕様のプロンプトで作ってある。
        generation_tier="premium",
        lang=lang,
    )


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--in", dest="src", default="scripts/corpus/corpus.jsonl")
    parser.add_argument("--out-dir", default="scripts/corpus/bank")
    parser.add_argument("--denylist", default="scripts/word_denylist.json")
    parser.add_argument(
        "--usage",
        default="scripts/corpus/usage.jsonl",
        help="cmd/usagefill のサイドカー。無ければ使い方の項目を入れない",
    )
    parser.add_argument("--max-rank", type=int, default=0, help="0 なら制限なし")
    args = parser.parse_args()

    deny = load_denylist(args.denylist)
    usage = load_usage(args.usage)
    os.makedirs(args.out_dir, exist_ok=True)

    # (target_word, topic) が重なったら後勝ち。pack_corpus.py と同じ扱い。
    rows = OrderedDict()
    dropped = {"error": 0, "deny": 0, "rank": 0, "blank": 0}
    with open(args.src, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            row = json.loads(line)
            if row.get("error"):
                dropped["error"] += 1
                continue
            if row["target_word"] in deny:
                dropped["deny"] += 1
                continue
            if args.max_rank and row["key_word_rank"] > args.max_rank:
                dropped["rank"] += 1
                continue
            if not all(row.get(lang) for lang in LANGS):
                dropped["blank"] += 1
                continue
            rows[(row["target_word"], row["topic"])] = row

    for lang in LANGS:
        out = os.path.join(args.out_dir, f"corpus_sentences_{lang}.json")
        with open(out, "w", encoding="utf-8") as f:
            json.dump(
                [
                    to_sentence(row, lang, usage.get(row["thai_text"]))
                    for row in rows.values()
                ],
                f,
                ensure_ascii=False,
            )
        size = os.path.getsize(out) / 1024 / 1024
        print(f"{out}  {len(rows)}文  {size:.1f}MB")

    words = {word for word, _ in rows}
    filled = sum(1 for row in rows.values() if row["thai_text"] in usage)
    print(f"語 {len(words)}  落とした行 {dropped}")
    print(f"使い方つき {filled}文 / {len(rows)}文")


if __name__ == "__main__":
    main()
