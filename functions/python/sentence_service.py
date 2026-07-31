import asyncio
import json
import os
import subprocess
import sys
import threading
import time
from typing import Callable

from google.cloud import storage as gcs
from google.cloud.firestore_v1.client import Client as FirestoreClient

try:
    from .constants import FREE_TOPICS, TOPICS, build_response_schema
    from .llm_providers import (
        generate_sentence_async as _llm_generate_async,
    )
    from .llm_providers import (
        generate_sentence_sync as _llm_generate_sync,
    )
    from .prompts import (
        build_prompt_with_context,
        gate_topics_for_vocab,
        get_system_prompt,
    )
    from .uvm import get_session_words
except ImportError:
    from constants import FREE_TOPICS, TOPICS, build_response_schema
    from llm_providers import (
        generate_sentence_async as _llm_generate_async,
    )
    from llm_providers import (
        generate_sentence_sync as _llm_generate_sync,
    )
    from prompts import (
        build_prompt_with_context,
        gate_topics_for_vocab,
        get_system_prompt,
    )
    from uvm import get_session_words

_freq_rank: dict[str, int] | None = None
_nlp_enrich_with_nlp: Callable[[dict], dict] | None = None
_nlp_import_lock = threading.Lock()

# NLP ワーカー子プロセス（nlp_worker.py 参照）。インスタンス内で1本を共有し、
# concurrency>1 のリクエストは _nlp_worker_io_lock でパイプ上を直列化する。
# 子プロセス化しないと NLP 後処理が 2.1s → 4.4s に伸びる（2026-07-31 dev実測）。
_nlp_worker_proc: "subprocess.Popen[str] | None" = None
_nlp_worker_lock = threading.Lock()  # 起動の排他
_nlp_worker_io_lock = threading.Lock()  # パイプ入出力の排他


def _get_enrich_with_nlp() -> Callable[[dict], dict]:
    """NLPの重い依存を必要になるまで読み込まない（ワーカー使用不可時のフォールバック）。"""
    global _nlp_enrich_with_nlp
    if _nlp_enrich_with_nlp is not None:
        return _nlp_enrich_with_nlp

    with _nlp_import_lock:
        if _nlp_enrich_with_nlp is None:
            started = time.perf_counter()
            from nlp import enrich_with_nlp

            # このパスの import は丸ごとリクエストの待ち時間になる。
            print(
                "NLP in-process import: "
                f"{round((time.perf_counter() - started) * 1000)}ms"
            )
            _nlp_enrich_with_nlp = enrich_with_nlp
        return _nlp_enrich_with_nlp


def _spawn_nlp_worker() -> "subprocess.Popen[str] | None":
    """NLP ワーカー子プロセスを起動する。失敗時は None。"""
    here = os.path.dirname(os.path.abspath(__file__))
    try:
        proc = subprocess.Popen(
            [sys.executable, "-u", os.path.join(here, "nlp_worker.py")],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=None,  # 子の stderr は Cloud Logging にそのまま流す
            cwd=here,
            text=True,
            bufsize=1,
        )
        proc._nlp_spawned_at = time.perf_counter()  # type: ignore[attr-defined]
        return proc
    except Exception as exc:
        print(f"NLP worker spawn failed: {exc}")
        return None


def _prewarm_nlp_async() -> None:
    """LLM の応答待ち中に、別プロセスで NLP import を先に走らせる。

    GIL はプロセス単位なので、子側のインポートは親のリクエスト処理を止めない。
    """
    global _nlp_worker_proc
    if _nlp_worker_proc is not None and _nlp_worker_proc.poll() is None:
        return

    with _nlp_worker_lock:
        if _nlp_worker_proc is not None and _nlp_worker_proc.poll() is None:
            return
        _nlp_worker_proc = _spawn_nlp_worker()


def _enrich_via_worker(sentence: dict) -> bool:
    """ワーカーで NLP 後処理を行う。成功したら sentence を書き換えて True。"""
    global _nlp_worker_proc

    proc = _nlp_worker_proc
    if (
        proc is None
        or proc.poll() is not None
        or proc.stdin is None
        or proc.stdout is None
    ):
        return False

    # 計測: ワーカーの import が LLM 待ちにどれだけ隠れたかを、インスタンスごとに
    # 1回だけログに残す。値を持つのは ready 行を読む最初の1回だけで、2回目以降は
    # 常に blocked=0 / import なしになるため出さない。
    timing: str | None = None

    with _nlp_worker_io_lock:
        try:
            # 起動直後の1回だけ ready 行を読み捨てる（インポート完了待ち）。
            if not getattr(proc, "_nlp_ready", False):
                wait_started = time.perf_counter()
                ready_line = proc.stdout.readline()
                blocked_ms = round((time.perf_counter() - wait_started) * 1000)
                if not ready_line:
                    raise RuntimeError("worker exited before ready")
                ready = json.loads(ready_line)
                if not ready.get("ready"):
                    raise RuntimeError(f"worker import failed: {ready.get('error')}")
                proc._nlp_ready = True  # type: ignore[attr-defined]
                spawned_at = getattr(proc, "_nlp_spawned_at", None)
                spawn_to_ready_ms = (
                    round((time.perf_counter() - spawned_at) * 1000)
                    if spawned_at is not None
                    else None
                )
                # blocked が 0 に近ければ import は LLM 待ちに隠れている＝ワーカーが
                # 効いている。child_import に近ければ隠せておらず、子プロセスにする
                # 意味がない（2026-07-31 のコールド実測では blocked=0）。
                timing = (
                    f"NLP timing: blocked={blocked_ms}ms "
                    f"child_import={ready.get('importMs')}ms "
                    f"spawn_to_ready={spawn_to_ready_ms}ms"
                )

            enrich_started = time.perf_counter()
            proc.stdin.write(
                json.dumps({"sentence": sentence}, ensure_ascii=False) + "\n"
            )
            proc.stdin.flush()
            line = proc.stdout.readline()
            if not line:
                raise RuntimeError("worker exited during enrich")
            enrich_ms = round((time.perf_counter() - enrich_started) * 1000)
            resp = json.loads(line)
            if not resp.get("ok"):
                raise RuntimeError(resp.get("error", "unknown worker error"))
        except Exception as exc:
            print(f"NLP worker failed, falling back in-process: {exc}")
            try:
                proc.kill()
            except Exception:
                pass
            _nlp_worker_proc = None
            return False

    if timing is not None:
        print(f"{timing} enrich={enrich_ms}ms")

    sentence.clear()
    sentence.update(resp["sentence"])
    return True


def _enrich_with_nlp(sentence: dict) -> None:
    """NLP 後処理を適用する。ワーカーが使えなければ同一プロセスで実行する。"""
    if _enrich_via_worker(sentence):
        return
    _get_enrich_with_nlp()(sentence)


def get_freq_rank() -> dict[str, int]:
    """GCS から freq_rank_top10000.json を読み込みキャッシュする。"""
    global _freq_rank
    if _freq_rank is not None:
        return _freq_rank

    project_id = os.environ.get("GCLOUD_PROJECT", "")
    bucket_name = f"{project_id}-uvm-data"
    client = gcs.Client()
    blob = client.bucket(bucket_name).blob("freq_rank_top10000.json")
    _freq_rank = json.loads(blob.download_as_text())
    return _freq_rank  # type: ignore


_free_sentences: list[dict] | None = None


def get_free_sentences() -> list[dict]:
    """GCS から free_sentences.json を読み込みキャッシュする。"""
    global _free_sentences
    if _free_sentences is not None:
        return _free_sentences

    project_id = os.environ.get("GCLOUD_PROJECT", "")
    bucket_name = f"{project_id}-uvm-data"
    client = gcs.Client()
    blob = client.bucket(bucket_name).blob("free_sentences.json")
    _free_sentences = json.loads(blob.download_as_text())
    return _free_sentences  # type: ignore


def pick_free_sentence(target_word: str) -> dict | None:
    """事前生成済みの free 例文から target_word に一致するものをランダムに返す。"""
    sentences = get_free_sentences()
    candidates = [s for s in sentences if s.get("key_word") == target_word]
    if not candidates:
        return None
    import random

    return random.choice(candidates)


def select_uvm_target_words(
    db: FirestoreClient,
    uid: str,
    params: dict,
    max_vocab: int | None = None,
    count: int = 1,
    is_premium: bool = True,
    estimated_vocab: int | None = None,
) -> tuple[list[str], str]:
    """UVMから例文生成用のターゲット単語を選定する。

    key_word先行方式: 帯域内からkey_wordを選出し、embeddingで最適テーマを決定する。
    テーマが明示指定されている場合はそのまま使用する。
    """
    freq_rank = get_freq_rank()
    topic = params.get("topic", "")
    if topic:
        topics_pool = None
    else:
        topic_candidates = TOPICS if is_premium else FREE_TOPICS
        topics_pool = (
            gate_topics_for_vocab(topic_candidates, estimated_vocab or 0)
            if is_premium
            else topic_candidates
        )
    return get_session_words(
        db,
        uid,
        freq_rank,
        topic=topic,
        count=count,
        max_vocab=max_vocab,
        topics_pool=topics_pool,
        estimated_vocab=estimated_vocab,
    )


def require_target_words(result: tuple[list[str], str]) -> tuple[list[str], str]:
    """ターゲット単語が空でないことを保証する。"""
    words, topic = result
    if not words:
        raise RuntimeError("No target words selected from UVM")
    return words, topic


MAX_RETRY = 1


def _match_word(word_text: str, target: str) -> bool:
    w = word_text.strip()
    return w == target or w == target + "ๆ" or w + "ๆ" == target


def validate_target_words(sentence: dict, target_words: list[str] | None) -> list[str]:
    """word_breakdownにtarget_wordが独立エントリとして存在するか検証する。

    複合語の一部としてのみ含まれるケースはmissingとして扱い、リトライで
    独立した形での使用を強制する。

    Returns:
        含まれていなかった単語のリスト（空なら全て含まれている）
    """
    if not target_words:
        return []

    wb_words = {
        str(wb.get("word", "")).strip()
        for wb in sentence.get("word_breakdown", [])
        if isinstance(wb, dict)
    }

    missing: list[str] = []
    for tw in target_words:
        target_word = str(tw).strip()
        if not target_word:
            continue
        if any(_match_word(w, target_word) for w in wb_words):
            continue
        missing.append(target_word)
    return missing


_CONTEXT_FIELDS = ("topic", "style", "emotion")


def _schema_for(resolved_context: dict | None) -> dict:
    """確定値が無い context フィールドだけ LLM に生成させるスキーマを返す。"""
    resolved = resolved_context or {}
    ask = tuple(f for f in _CONTEXT_FIELDS if not resolved.get(f))
    return build_response_schema(ask)


def _apply_response_compat(sentence: dict, resolved_context: dict | None) -> dict:
    """LLM の省トークン形式を、保存・クライアント互換の形に戻す。

    - target_notes を word_breakdown[].notes に展開する（非対象は空文字）
    - context.topic / style / emotion にサーバー確定値を注入する
    """
    notes_by_word = {
        str(item.get("word", "")).strip(): str(item.get("note", ""))
        for item in sentence.pop("target_notes", []) or []
        if isinstance(item, dict)
    }
    for wb in sentence.get("word_breakdown", []):
        if not isinstance(wb, dict):
            continue
        word = str(wb.get("word", "")).strip()
        note = notes_by_word.get(word, "")
        if not note:
            note = next(
                (n for w, n in notes_by_word.items() if _match_word(word, w)),
                "",
            )
        wb["notes"] = note

    if resolved_context:
        context = sentence.get("context")
        sentence["context"] = {
            **(context if isinstance(context, dict) else {}),
            **resolved_context,
        }

    return sentence


def _build_retry_prompt(prompt: str, missing: list[str]) -> str:
    missing_str = ", ".join(missing)
    return (
        f"{prompt}\n\n"
        f"【再生成指示】前回の生成では次の単語がword_breakdownに独立エントリとして含まれていませんでした: {missing_str}\n"
        f"これらの単語を複合語の一部ではなく、単独で意味が成り立つ形で文中に使い、word_breakdownにも独立した項目として含めてください。"
    )


def _generate_single(
    system_prompt: str,
    prompt: str,
    is_premium: bool,
    tier_label: str,
    target_words: list[str] | None = None,
    resolved_context: dict | None = None,
) -> dict:
    """LLM で1文を同期生成し NLP 後処理を適用する。"""
    _prewarm_nlp_async()
    sentence: dict = {}
    current_prompt = prompt
    missing: list[str] = []
    for attempt in range(1 + MAX_RETRY):
        sentence = _llm_generate_sync(
            system_prompt,
            current_prompt,
            is_premium,
            tier_label,
            _schema_for(resolved_context),
        )
        _apply_response_compat(sentence, resolved_context)
        _enrich_with_nlp(sentence)

        missing = validate_target_words(sentence, target_words)
        if not missing:
            return sentence

        print(
            f"Target word validation failed (attempt {attempt + 1}): missing={missing}"
        )
        current_prompt = _build_retry_prompt(prompt, missing)

    raise RuntimeError(
        f"LLM_API_ERROR: target words missing after retries: {', '.join(missing)}"
    )


async def _generate_single_async(
    system_prompt: str,
    prompt: str,
    is_premium: bool,
    tier_label: str,
    target_words: list[str] | None = None,
    resolved_context: dict | None = None,
) -> dict:
    """LLM で1文を非同期生成し NLP 後処理を適用する（バッチ並列用）。"""
    _prewarm_nlp_async()
    sentence: dict = {}
    current_prompt = prompt
    missing: list[str] = []
    for attempt in range(1 + MAX_RETRY):
        sentence = await _llm_generate_async(
            system_prompt,
            current_prompt,
            is_premium,
            tier_label,
            _schema_for(resolved_context),
        )
        _apply_response_compat(sentence, resolved_context)
        _enrich_with_nlp(sentence)

        missing = validate_target_words(sentence, target_words)
        if not missing:
            return sentence

        print(
            f"Target word validation failed (attempt {attempt + 1}): missing={missing}"
        )
        current_prompt = _build_retry_prompt(prompt, missing)

    raise RuntimeError(
        f"LLM_API_ERROR: target words missing after retries: {', '.join(missing)}"
    )


def generate_sentence(
    params: dict,
    is_premium: bool,
    *,
    target_words: list[str] | None = None,
    estimated_vocab: int = 0,
) -> dict:
    """LLM で例文を生成し、NLP後処理を適用する。"""
    tier_label = "premium" if is_premium else "free"
    prompt, resolved_context = build_prompt_with_context(
        params,
        target_words,
        estimated_vocab=estimated_vocab,
        is_premium=is_premium,
    )
    system_prompt = get_system_prompt(is_premium, estimated_vocab)
    return _generate_single(
        system_prompt,
        prompt,
        is_premium,
        tier_label,
        target_words,
        resolved_context,
    )


async def _generate_batch_async(
    count: int,
    is_premium: bool,
    *,
    all_target_words: list[list[str]],
    all_topics: list[str],
    estimated_vocab: int = 0,
) -> list[dict]:
    """複数の例文を asyncio.gather で並列生成する。"""
    tier_label = "premium" if is_premium else "free"
    tasks = []
    for i in range(count):
        tw = all_target_words[i] if i < len(all_target_words) else None
        topic = all_topics[i] if i < len(all_topics) else ""
        prompt, resolved_context = build_prompt_with_context(
            {"topic": topic} if topic else {},
            tw,
            estimated_vocab=estimated_vocab,
            is_premium=is_premium,
        )
        system_prompt = get_system_prompt(is_premium, estimated_vocab)
        tasks.append(
            _generate_single_async(
                system_prompt,
                prompt,
                is_premium,
                tier_label,
                tw,
                resolved_context,
            )
        )

    results = await asyncio.gather(*tasks, return_exceptions=True)

    sentences: list[dict] = []
    for idx, r in enumerate(results):
        if isinstance(r, BaseException):
            raise RuntimeError(f"LLM_API_ERROR: batch generation failed: {r}") from r
        sentences.append(r)
    return sentences


def generate_sentences_batch(
    count: int,
    is_premium: bool,
    *,
    all_target_words: list[list[str]],
    all_topics: list[str],
    estimated_vocab: int = 0,
) -> list[dict]:
    """複数の例文を並列で生成する（sync ラッパー）。"""
    return asyncio.run(
        _generate_batch_async(
            count,
            is_premium,
            all_target_words=all_target_words,
            all_topics=all_topics,
            estimated_vocab=estimated_vocab,
        )
    )
