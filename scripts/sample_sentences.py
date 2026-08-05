"""prompts.py の現行プロンプトでオフラインに例文を量産する。

Firestore もクォータも通さず LLM だけ叩くため、プロンプト修正 → 生成 → 目視レビューを
高速に回せる。デプロイ前の検証用。

usage:
  cd functions/python
  GCLOUD_PROJECT=thai-memo-dev uv run python ../../scripts/sample_sentences.py -n 20 --vocab 150
"""

import argparse
import json
import os
import random
import time
import sys
from concurrent.futures import ThreadPoolExecutor

import certifi

# llm_providers は urllib を使うため、ローカル実行では CA バンドルの明示が要る。
os.environ.setdefault("SSL_CERT_FILE", certifi.where())

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "functions", "python"))

from sentence_service import _schema_for  # noqa: E402
from llm_providers import generate_sentence_sync  # noqa: E402
from prompts import build_prompt_with_context, get_system_prompt  # noqa: E402


# prod の実ユーザー165人の estimated_vocab 分布（2026-08-03 実測）。
# 0 が 94人 / 1-99 が 69人 / 100-299 が 2人。中央値 0・p90 25。
# --vocab 未指定時はこの分布から引き、実運用に近い難易度で生成する。
VOCAB_DISTRIBUTION: list[tuple[tuple[int, int], float]] = [
    ((0, 0), 0.57),
    ((1, 99), 0.42),
    ((100, 299), 0.01),
]


def sample_vocab() -> int:
    (lo, hi), _ = random.choices(
        VOCAB_DISTRIBUTION, weights=[w for _, w in VOCAB_DISTRIBUTION], k=1
    )[0]
    return random.randint(lo, hi)


def load_freq_rank() -> dict[str, int]:
    from google.cloud import storage

    project_id = os.environ.get("GCLOUD_PROJECT", "")
    if not project_id:
        raise RuntimeError("GCLOUD_PROJECT を設定してください")
    blob = (
        storage.Client()
        .bucket(f"{project_id}-uvm-data")
        .blob("freq_rank_top10000.json")
    )
    return json.loads(blob.download_as_text())


# 文語・古語・単独で立たない形態素。key_word に来ると例文が必ず壊れるため引かない。
# 本体側の除外ロジックが入ったらそちらを import して置き換える。
EXCLUDED_KEY_WORDS = frozenset({"มิ", "ข้า", "ริ", "น่า", "ที", "ณ", "เจ้า", "ไอ้"})


def pick_key_word(freq_rank: dict[str, int], vocab: int) -> str:
    """estimated_vocab 帯の前後から key_word を1語引く（UVM の帯域選出を模した近似）。"""
    lo, hi = max(0, int(vocab * 0.5)), max(200, int(vocab * 1.5))
    band = [
        w
        for w, r in freq_rank.items()
        if lo <= r <= hi and w not in EXCLUDED_KEY_WORDS
    ]
    return random.choice(band or list(freq_rank))


def generate_one(
    freq_rank: dict[str, int],
    vocab: int | None,
    is_premium: bool,
    word: str | None = None,
    topic: str | None = None,
) -> dict:
    if vocab is None:
        vocab = sample_vocab()
    word = word or pick_key_word(freq_rank, vocab)
    params: dict = {}
    # 本体（uvm.get_session_words）は key_word の embedding からテーマを選ぶ。
    # ここでランダムにすると語とテーマが噛み合わない文が人工的に増えるため揃える。
    if not topic:
        from constants import TOPICS
        from embeddings import find_best_topic
        from prompts import gate_topics_for_vocab

        pool = gate_topics_for_vocab(list(TOPICS), vocab)
        topic = find_best_topic(word, pool, top_k=5, threshold=0.545) or random.choice(
            pool
        )
    if topic:
        params["topic"] = topic
    prompt, context = build_prompt_with_context(
        params,
        [word],
        estimated_vocab=vocab,
        is_premium=is_premium,
    )
    system = get_system_prompt(is_premium, vocab)
    started = time.monotonic()
    try:
        s = generate_sentence_sync(
            system,
            prompt,
            is_premium,
            "premium" if is_premium else "free",
            # 本番と同じく、サーバーが確定しなかった context だけ LLM に書かせる。
            _schema_for(context),
        )
    except Exception as exc:  # 1件の失敗で全体を落とさない
        return {"key_word": word, "error": str(exc), "sec": round(time.monotonic() - started, 2)}
    register = [
        line.strip("- ")
        for line in prompt.splitlines()
        if line.startswith(("- 文体:", "- 丁寧さ:"))
    ]
    # 文法フォーカス・感情も記録する。文体違反の判定にはこの2つが要る
    # （疑問文フォーカスならニュース体でも疑問文が正解になる等）。
    extras = {
        line.split(":", 1)[0].strip("- "): line.split(":", 1)[1].strip()
        for line in prompt.splitlines()
        if line.startswith(
            ("- 話している時点:",)
        )
    }
    return {
        "key_word": word,
        "vocab": vocab,
        # レイテンシは常設で記録する（reasoning effort・並列数を変えたときの比較用）。
        "sec": round(time.monotonic() - started, 2),
        "topic": context.get("topic"),
        "register": " / ".join(register),
        "grammar": extras.get("文法フォーカス"),
        "emotion": extras.get("感情・トーン"),
        "time_frame": extras.get("話している時点"),
        # 文体はサーバーで確定しないので、LLM が実際に書いた文体を受け取る。
        "style_llm": (s.get("context") or {}).get("style"),
        "modality": extras.get("述べ方"),
        "thai": s.get("thai_text"),
        "ja": s.get("japanese_translation"),
        "words": [
            (w.get("word"), w.get("meaning")) for w in (s.get("word_breakdown") or [])
        ],
    }


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("-n", type=int, default=20, help="生成件数")
    p.add_argument(
        "--vocab",
        type=int,
        default=None,
        help="estimated_vocab を固定する。未指定なら prod の実分布から引く",
    )
    p.add_argument("--free", action="store_true", help="free プロンプトを使う")
    p.add_argument(
        "--words",
        default=None,
        help="key_word をカンマ区切りで固定する（機能語だけを狙って検証するとき用）",
    )
    p.add_argument(
        "--topic",
        default=None,
        help="TOPICS の完全一致文字列、または部分一致するテーマ名でトピックを固定する",
    )
    p.add_argument("--out", default="/tmp/samples.json")
    p.add_argument(
        "--workers", type=int, default=8, help="並列数。API 側に切られるときは下げる"
    )
    args = p.parse_args()

    freq_rank = load_freq_rank()
    is_premium = not args.free
    fixed = [w.strip() for w in args.words.split(",")] if args.words else None
    topic = None
    if args.topic:
        from constants import TOPICS

        matched = [t for t in TOPICS if args.topic in t]
        if not matched:
            raise SystemExit(f"テーマが見つかりません: {args.topic}")
        topic = matched[0]
    with ThreadPoolExecutor(max_workers=args.workers) as ex:
        results = list(
            ex.map(
                lambda i: generate_one(
                    freq_rank,
                    args.vocab,
                    is_premium,
                    fixed[i % len(fixed)] if fixed else None,
                    topic,
                ),
                range(args.n),
            )
        )

    with open(args.out, "w") as f:
        json.dump(results, f, ensure_ascii=False, indent=1)

    for i, r in enumerate(results):
        if r.get("error"):
            print(f"{i:3d} ERROR {r['key_word']}: {r['error']}")
            continue
        print(
            f"{i:3d} kw={r['key_word']} vocab={r['vocab']} "
            f"[{(r['topic'] or '')[:8]}] {r.get('register', '')}"
            f" / LLM文体: {r.get('style_llm')}"
        )
        print(f"    T: {r['thai']}")
        print(f"    J: {r['ja']}")
    print(f"\n-> {args.out}", file=sys.stderr)


if __name__ == "__main__":
    main()
