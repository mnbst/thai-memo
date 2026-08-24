"""free 例文バンク（GCS free_sentences_<lang>.json）を現行プロンプトで作り直す。

free ティアの例文は LLM ではなくこのバンクから引かれる（sentence_service.pick_free_sentence）。
バンクが古いとプロンプト改善が free ユーザーに一切届かず、同じ文が使い回される。

生成は本番と同じ経路（prompts.build_prompt_with_context → llm_providers.generate_sentence_sync）
を通すので、prompts.py を直せばそのままバンクに反映される。

usage:
  cd functions/python
  GCLOUD_PROJECT=thai-memo-prod uv run python ../../scripts/build_free_sentence_bank.py \
      --lang ja,en --per-word 4 --max-rank 114 --out ../../scripts/bank_out
  # 確認後にアップロード
  GCLOUD_PROJECT=thai-memo-prod uv run python ../../scripts/build_free_sentence_bank.py \
      --upload-only --out ../../scripts/bank_out
"""

import argparse
import json
import os
import random
import sys
import time
from collections import Counter
from concurrent.futures import ThreadPoolExecutor, as_completed

import certifi

# llm_providers は urllib を使うため、ローカル実行では CA バンドルの明示が要る。
os.environ.setdefault("SSL_CERT_FILE", certifi.where())

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "functions", "python"))

from constants import BL_TOPIC, FREE_BL_TOPIC_RATE, TOPICS  # noqa: E402
from prompts import gate_topics_for_vocab  # noqa: E402
from sentence_service import generate_sentence  # noqa: E402

# 文語・古語・単独で立たない形態素。key_word に来ると例文が必ず壊れる。
# sample_sentences.py と同じ集合（本体に除外ロジックが入ったらそちらへ寄せる）。
EXCLUDED_KEY_WORDS = frozenset({"มิ", "ข้า", "ริ", "น่า", "ที", "ณ", "เจ้า", "ไอ้"})

# 入門帯の上限（DIFFICULTY_LEVELS の入門は max_vocab=99）。
INTRO_MAX_VOCAB = 99

# ─── 文体マーカー（--refresh-markers 用、2026-08-22 追加） ───
# free/premium の文体差は語彙ではなくこの4つに出る。free spec と premium spec を
# 同条件10文ずつで測った実測値（主語明示 40/10%、口語終助詞 0/20%、丁寧終助詞
# 40/0%、アスペクト 10/40%、接続標識 0/10%、2節 0/30%）から、機械判定できる
# 4つを採った。主語明示・丁寧終助詞は「教科書的な側」に出るマーカーなので数えない
# （消す対象ではない）。
_COLLOQUIAL_PARTICLES = ("จัง", "นะ", "เลย", "กัน", "สิ", "หรอก", "ล่ะ", "แหละ",
                         "ว่ะ", "เนอะ")
_ASPECT_MARKERS = ("เพิ่ง", "มาแล้ว", "กำลัง", "เมื่อกี้", "ประจำ", "เคย", "ไว้", "อยู่")
# เลย は _COLLOQUIAL_PARTICLES と両方に該当する（強調の終助詞と「だから」の
# 接続詞の両用）。両方に置くと เลย 1語だけでマーカーが2つ立ち、教科書的な文まで
# 差し替え対象になった（現行448では対象 46文中 11文がこれ）。1語は1つだけ数える。
_CONNECTIVES = ("แต่", "เพราะ", "ก็", "ถ้า", "พอ", "จน")


def count_style_markers(thai_text: str, key_word: str = "") -> int:
    """premium 寄りの文体マーカーがいくつ立っているかを返す。

    0 なら教科書的（入門教材の例文と同じ形）。現行バンク448文の分布は
    0:266 / 1:147 / 2:32 / 3:3。

    key_word 自体はマーカーから除く。ターゲット語が แต่/ถ้า/เคย/ไว้ のときは
    その語が文に必ず入るので、数えると何度引き直しても下がらない
    （引き直し3回でも下がらなかった6文が全てこのケースだった）。
    """
    text = thai_text or ""

    def hit(markers: tuple[str, ...]) -> bool:
        return any(k in text for k in markers if k != key_word)

    n = 0
    if hit(_COLLOQUIAL_PARTICLES):
        n += 1
    if hit(_ASPECT_MARKERS):
        n += 1
    if hit(_CONNECTIVES):
        n += 1
    if " " in text:  # 2節
        n += 1
    return n


def load_freq_rank(project_id: str) -> dict[str, int]:
    from google.cloud import storage

    blob = (
        storage.Client(project=project_id)
        .bucket(f"{project_id}-uvm-data")
        .blob("freq_rank_top10000.json")
    )
    return json.loads(blob.download_as_text())


def build_jobs(words: list[tuple[str, int]], per_word: int) -> list[tuple[str, int, str]]:
    """(word, rank, topic) のジョブを、テーマが均等になるように割り当てる。

    2026-08-14 変更: embedding の argmax（find_best_topic）をやめた。テーマ
    embedding は語彙全体への平均類似度に差があり、重心の高いテーマが全語で
    argmax になる（free 4テーマでは BLドラマが 82.7%、旧バンク生成では旅行が
    59%）。バンクは free ユーザーが実際に読む中身なので、語との相性より
    テーマの均等さを優先する。同じ語には毎回違うテーマを当てる。

    テーマは rank に関係なく入門6テーマに固定する。バンクは free だけが読む
    キャッシュで、free の estimated_vocab は 100 でキャップされる。rank 100〜114 の
    語にだけ 仕事/交通/健康/趣味/恋愛 を解禁しても、専門語彙（ประชุม・อาการ・
    ผี など）が混ざって基本文から外れるだけだった。

    BL だけは別枠。語彙ゲート（min_vocab=100）に掛かって入門帯にはほぼ
    出ないが、刺さる層への引きとして FREE_BL_TOPIC_RATE の割合を確保する
    （本体の free 経路と同じ率。sentence_service.select_uvm_target_words）。
    """
    used: Counter[str] = Counter()
    jobs: list[tuple[str, int, str]] = []
    intro_pool = [t for t in gate_topics_for_vocab(list(TOPICS), 0) if t != BL_TOPIC]
    for word, rank in words:
        pool = intro_pool
        if not pool:
            jobs.extend((word, rank, "") for _ in range(per_word))
            continue
        for _ in range(per_word):
            # 使用回数が最小のテーマから選ぶ（同数はランダムで崩す）。
            fewest = min(used.get(t, 0) for t in pool)
            topic = random.choice([t for t in pool if used.get(t, 0) == fewest])
            used[topic] += 1
            jobs.append((word, rank, topic))

    # BL 枠は割り当て済みジョブから抽選で差し替える（語の偏りを避けるため）。
    quota = round(len(jobs) * FREE_BL_TOPIC_RATE)
    for i in random.sample(range(len(jobs)), min(quota, len(jobs))):
        word, rank, _ = jobs[i]
        jobs[i] = (word, rank, BL_TOPIC)
    return jobs


def generate_one(
    word: str, rank: int, topic: str, lang: str, is_premium: bool
) -> dict | None:
    """1文生成する。失敗した語は落として次へ（1件の失敗で全体を止めない）。

    本番と同じ sentence_service.generate_sentence を通す。target_notes の展開・
    タイ語スペース正規化・PyThaiNLP による発音/音節付与まで含めて同一処理になる。
    """
    # 旧バンクと同じく、その語が出る頃の語彙量を estimated_vocab に使う。
    # 難易度（長さヒント・語彙レベル）がその語を学ぶ人の実態に揃う。
    # ただし入門帯（99）で頭打ちにする。free は estimated_vocab が 100 で
    # キャップされるので、バンクだけ初級スペック（語彙ヒントが緩む・7単語）で
    # 作ると、読む側のレベルより難しい文が混ざる。
    vocab = min(rank, INTRO_MAX_VOCAB)
    params: dict = {}
    if topic:
        params["topic"] = topic
    try:
        s = generate_sentence(
            params,
            is_premium,
            target_words=[word],
            estimated_vocab=vocab,
            lang=lang,
        )
    except Exception as exc:
        print(f"  ! {word} ({lang}): {exc}", file=sys.stderr)
        return None
    if not (s.get("thai_text") or "").strip():
        return None
    return {
        "key_word": word,
        "key_word_rank": rank,
        "estimated_vocab": vocab,
        "thai_text": s.get("thai_text"),
        "pronunciation": s.get("pronunciation"),
        # フィールド名は japanese_translation のまま（en でも英文がここに入る）。
        "japanese_translation": s.get("japanese_translation"),
        "word_breakdown": s.get("word_breakdown") or [],
        "context": s.get("context") or {},
        "generation_tier": "free",
    }


def build(lang: str, words: list[tuple[str, int]], per_word: int,
          is_premium: bool, workers: int) -> list[dict]:
    jobs = build_jobs(words, per_word)
    out: list[dict] = []
    seen: set[str] = set()
    started = time.monotonic()
    with ThreadPoolExecutor(max_workers=workers) as ex:
        futs = {
            ex.submit(generate_one, w, r, t, lang, is_premium): (w, r)
            for w, r, t in jobs
        }
        done = 0
        for fut in as_completed(futs):
            done += 1
            s = fut.result()
            if done % 50 == 0:
                print(f"  {lang}: {done}/{len(jobs)} "
                      f"({time.monotonic() - started:.0f}s)", file=sys.stderr)
            if s is None:
                continue
            # 同じ文が複数ユーザーに配られるのを避けるため、バンク内では重複を捨てる。
            if s["thai_text"] in seen:
                continue
            seen.add(s["thai_text"])
            out.append(s)
    out.sort(key=lambda x: (x["key_word_rank"], x["thai_text"]))
    return out


def download_bank(project_id: str, lang: str) -> list[dict]:
    """GCS の現行バンクを読む（--refresh-markers 用）。"""
    from google.cloud import storage

    blob = (
        storage.Client(project=project_id)
        .bucket(f"{project_id}-uvm-data")
        .blob(f"free_sentences_{lang}.json")
    )
    return json.loads(blob.download_as_text())


def refresh(lang: str, bank: list[dict], threshold: int, workers: int,
            retries: int) -> list[dict]:
    """マーカーが threshold 以上の文だけ free spec で作り直す。

    key_word・rank・テーマは元の行から引き継ぐ。バンク全体を作り直すと、
    すでに教科書的な文（現行448中266文）の多様性まで振り直すことになるので、
    置き換えるのは外れた文だけにする。

    作り直した文がまた threshold 以上なら retries 回まで引き直し、それでも
    下がらなければ元の文を残す（穴を空けない）。
    """
    def score(row: dict) -> int:
        return count_style_markers(row.get("thai_text", ""), row.get("key_word", ""))

    keep = [x for x in bank if score(x) < threshold]
    targets = [x for x in bank if score(x) >= threshold]
    print(f"[{lang}] 据え置き {len(keep)}文 / 作り直し {len(targets)}文")
    seen = {x.get("thai_text") for x in bank}
    started = time.monotonic()

    def regenerate(row: dict) -> dict:
        word = row["key_word"]
        rank = row.get("key_word_rank", INTRO_MAX_VOCAB)
        topic = (row.get("context") or {}).get("topic") or ""
        for _ in range(retries):
            s = generate_one(word, rank, topic, lang, is_premium=False)
            if s is None:
                continue
            text = s.get("thai_text")
            if text in seen:
                continue
            if count_style_markers(text, word) >= threshold:
                continue
            seen.add(text)
            return s
        print(f"  ! {word} ({lang}): {retries}回引いても下がらず元の文を残す",
              file=sys.stderr)
        return row

    out = list(keep)
    with ThreadPoolExecutor(max_workers=workers) as ex:
        futs = {ex.submit(regenerate, r): r for r in targets}
        done = 0
        for fut in as_completed(futs):
            done += 1
            if done % 10 == 0:
                print(f"  {lang}: {done}/{len(targets)} "
                      f"({time.monotonic() - started:.0f}s)", file=sys.stderr)
            out.append(fut.result())
    out.sort(key=lambda x: (x["key_word_rank"], x["thai_text"]))
    return out


def upload(project_id: str, lang: str, path: str) -> None:
    from google.cloud import storage

    blob = (
        storage.Client(project=project_id)
        .bucket(f"{project_id}-uvm-data")
        .blob(f"free_sentences_{lang}.json")
    )
    blob.upload_from_filename(path, content_type="application/json")
    print(f"uploaded → gs://{project_id}-uvm-data/free_sentences_{lang}.json")


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--lang", default="ja,en", help="生成する訳文言語（カンマ区切り）")
    p.add_argument("--per-word", type=int, default=4, help="key_word あたりの生成数")
    p.add_argument("--max-rank", type=int, default=114,
                   help="頻度順位の上限。free 上限は100だが旧バンクは114まで持つ")
    p.add_argument("--words", type=int, default=0,
                   help="デバッグ用: 先頭N語だけ生成する（0で全語）")
    p.add_argument("--spec", choices=("free", "premium"), default="premium",
                   help="生成に使うプロンプト。バンクは作り置きなので既定は premium "
                        "（語彙レジスタ制約が効き自然さが上がる。配信時の tier は free のまま）")
    p.add_argument("--refresh-markers", type=int, default=0,
                   help="0以外で差分更新モード。現行バンクのうち文体マーカーが"
                        "この数以上の文だけを free spec で作り直す（推奨: 2）")
    p.add_argument("--refresh-retries", type=int, default=3,
                   help="--refresh-markers で引き直す最大回数（既定3）")
    p.add_argument("--workers", type=int, default=8)
    p.add_argument("--out", default="scripts/bank_out")
    p.add_argument("--upload", action="store_true", help="生成後にGCSへ上げる")
    p.add_argument("--upload-only", action="store_true", help="生成済みJSONを上げるだけ")
    a = p.parse_args()

    project_id = os.environ.get("GCLOUD_PROJECT", "")
    if not project_id:
        sys.exit("GCLOUD_PROJECT を設定してください")
    os.makedirs(a.out, exist_ok=True)
    langs = [x.strip() for x in a.lang.split(",") if x.strip()]

    if a.upload_only:
        for lang in langs:
            upload(project_id, lang, os.path.join(a.out, f"free_sentences_{lang}.json"))
        return

    if a.refresh_markers:
        for lang in langs:
            bank = download_bank(project_id, lang)
            rows = refresh(lang, bank, a.refresh_markers, a.workers,
                           a.refresh_retries)
            path = os.path.join(a.out, f"free_sentences_{lang}.json")
            with open(path, "w", encoding="utf-8") as f:
                json.dump(rows, f, ensure_ascii=False, indent=1)
            dist = Counter(
                count_style_markers(x["thai_text"], x.get("key_word", ""))
                for x in rows
            )
            print(f"[{lang}] {len(rows)}文 / マーカー分布 "
                  f"{dict(sorted(dist.items()))} → {path}")
            if a.upload:
                upload(project_id, lang, path)
        return

    freq_rank = load_freq_rank(project_id)
    words = sorted(
        ((w, r) for w, r in freq_rank.items()
         if r <= a.max_rank and w not in EXCLUDED_KEY_WORDS),
        key=lambda x: x[1],
    )
    if a.words:
        words = words[: a.words]
    print(f"project={project_id} 対象 key_word {len(words)}語 × {a.per_word}文 "
          f"× {len(langs)}言語 = {len(words) * a.per_word * len(langs)} 回生成 "
          f"(spec={a.spec})")

    for lang in langs:
        rows = build(lang, words, a.per_word, a.spec == "premium", a.workers)
        path = os.path.join(a.out, f"free_sentences_{lang}.json")
        with open(path, "w", encoding="utf-8") as f:
            json.dump(rows, f, ensure_ascii=False, indent=1)
        per = Counter(x["key_word"] for x in rows)
        missing = [w for w, _ in words if w not in per]
        print(f"[{lang}] {len(rows)}文 / {len(per)}語 / 文数分布 "
              f"{dict(sorted(Counter(per.values()).items()))} → {path}")
        if missing:
            print(f"[{lang}] 生成できなかった語 {len(missing)}: {' '.join(missing[:20])}")
        if a.upload:
            upload(project_id, lang, path)


if __name__ == "__main__":
    main()
