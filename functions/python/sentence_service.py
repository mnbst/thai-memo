import asyncio
import json
import os
import random
import time

from google import genai
from google.cloud import secretmanager
from google.cloud import storage as gcs
from google.cloud.firestore_v1.client import Client as FirestoreClient

from constants import (
    API_MAX_TOKENS,
    API_TEMPERATURE,
    FREE_TOPICS,
    GEMINI_MODEL,
    GEMINI_MODEL_PREMIUM,
    RESPONSE_SCHEMA,
    TOPICS,
)
from nlp import enrich_with_nlp
from prompts import build_uvm_prompt
from uvm import get_session_words

_freq_rank: dict[str, int] | None = None
_gemini_api_key: str | None = None
_gemini_api_key_fetched_at: float = 0.0
_GEMINI_KEY_TTL_SECONDS: float = 3600.0  # 1時間


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


def get_gemini_api_key() -> str:
    global _gemini_api_key, _gemini_api_key_fetched_at
    if _gemini_api_key is not None and (time.monotonic() - _gemini_api_key_fetched_at) < _GEMINI_KEY_TTL_SECONDS:
        return _gemini_api_key

    client = secretmanager.SecretManagerServiceClient()
    project_id = os.environ.get("GCLOUD_PROJECT", "")
    name = f"projects/{project_id}/secrets/gemini-api-key/versions/latest"
    response = client.access_secret_version(request={"name": name})
    api_key = response.payload.data.decode("UTF-8")
    if not api_key:
        raise RuntimeError("SECRET_MANAGER_ERROR")
    _gemini_api_key = api_key
    _gemini_api_key_fetched_at = time.monotonic()
    return api_key


def select_uvm_target_words(
    db: FirestoreClient,
    uid: str,
    params: dict,
    api_key: str | None = None,
    max_vocab: int | None = None,
    count: int = 1,
    is_premium: bool = True,
    estimated_vocab: int | None = None,
) -> tuple[list[str], str]:
    """UVMから例文生成用のターゲット単語を選定する。

    key_word先行方式: 帯域内からkey_wordを選出し、embeddingで最適トピックを決定する。
    トピックが明示指定されている場合はそのまま使用する。

    Args:
        max_vocab: 語彙帯域の上限。free ティアでは 300 に制限。
        count: 選定する単語数。
        is_premium: プレミアムティアかどうか。
        estimated_vocab: 呼び出し元で取得済みの推定語彙数。省略時は Firestore から読む。

    Returns:
        (選定された単語リスト, 使用されたトピック)
    """
    freq_rank = get_freq_rank()
    topic = params.get("topic", "")
    topics_pool = None if topic else (TOPICS if is_premium else FREE_TOPICS)
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


def validate_target_words(sentence: dict, target_words: list[str] | None) -> list[str]:
    """生成された例文にtarget_wordsが含まれているか検証する。

    thai_text またはword_breakdown内のwordフィールドに含まれていればOK。

    Returns:
        含まれていなかった単語のリスト（空なら全て含まれている）
    """
    if not target_words:
        return []

    thai_text = sentence.get("thai_text", "")
    wb_words = {
        str(wb.get("word", "")).strip()
        for wb in sentence.get("word_breakdown", [])
        if isinstance(wb, dict)
    }

    missing: list[str] = []
    for tw in target_words:
        if tw in wb_words or tw in thai_text:
            continue
        missing.append(tw)
    return missing


def _call_gemini_with_retry_sync(
    client: genai.Client,
    model: str,
    prompt: str,
    tier_label: str,
    *,
    max_retries: int = 3,
    base_delay: float = 2.0,
) -> genai.types.GenerateContentResponse:
    """Gemini API を同期呼び出しし、一時的エラー (503等) 時はexponential backoffでリトライする。"""
    for attempt in range(1 + max_retries):
        try:
            result = client.models.generate_content(
                model=model,
                contents=prompt,
                config=genai.types.GenerateContentConfig(
                    temperature=API_TEMPERATURE,
                    max_output_tokens=API_MAX_TOKENS,
                    response_mime_type="application/json",
                    response_schema=RESPONSE_SCHEMA,
                ),
            )
            return result
        except Exception as e:
            error_str = str(e)
            is_transient = any(
                code in error_str for code in ("503", "429", "UNAVAILABLE", "RESOURCE_EXHAUSTED")
            )
            if not is_transient or attempt == max_retries:
                raise
            delay = base_delay * (2 ** attempt) + random.uniform(0, 1)
            print(
                f"Gemini API transient error ({tier_label}, attempt {attempt + 1}/{max_retries}): "
                f"{e}. Retrying in {delay:.1f}s..."
            )
            time.sleep(delay)
    raise RuntimeError("Unreachable")


def _generate_single(
    client: genai.Client,
    model: str,
    prompt: str,
    tier_label: str,
    target_words: list[str] | None = None,
) -> dict:
    """Gemini API で1文を同期生成し NLP 後処理を適用する。

    target_words が指定されている場合、生成結果にそれらが含まれているか検証し、
    不足があれば最大 MAX_RETRY 回リトライする。
    """
    sentence: dict = {}
    current_prompt = prompt
    for attempt in range(1 + MAX_RETRY):
        result = _call_gemini_with_retry_sync(client, model, current_prompt, tier_label)
        if result.usage_metadata:
            print(
                f"Gemini token usage ({tier_label}): "
                f"input={result.usage_metadata.prompt_token_count}, "
                f"output={result.usage_metadata.candidates_token_count}, "
                f"total={result.usage_metadata.total_token_count}"
            )
        text = result.text
        if not text or not text.strip():
            raise RuntimeError("Empty response from Gemini API")
        sentence = json.loads(text)
        enrich_with_nlp(sentence)

        missing = validate_target_words(sentence, target_words)
        if not missing:
            return sentence

        print(
            f"Target word validation failed (attempt {attempt + 1}): "
            f"missing={missing}"
        )

        # リトライ時は不足単語を明示したプロンプトに差し替え
        missing_str = ", ".join(missing)
        current_prompt = (
            f"{prompt}\n\n"
            f"【再生成指示】前回の生成では次の単語が含まれていませんでした: {missing_str}\n"
            f"これらの単語を必ず文中に含めてください。"
        )

    # リトライ上限到達 — 生成自体は成功しているのでそのまま返す
    print(f"Returning sentence despite missing target words after {1 + MAX_RETRY} attempts")
    return sentence


async def _call_gemini_with_retry(
    client: genai.Client,
    model: str,
    prompt: str,
    tier_label: str,
    *,
    max_retries: int = 3,
    base_delay: float = 2.0,
) -> genai.types.GenerateContentResponse:
    """Gemini API を呼び出し、一時的エラー (503等) 時はexponential backoffでリトライする。"""
    for attempt in range(1 + max_retries):
        try:
            result = await client.aio.models.generate_content(
                model=model,
                contents=prompt,
                config=genai.types.GenerateContentConfig(
                    temperature=API_TEMPERATURE,
                    max_output_tokens=API_MAX_TOKENS,
                    response_mime_type="application/json",
                    response_schema=RESPONSE_SCHEMA,
                ),
            )
            return result
        except Exception as e:
            error_str = str(e)
            is_transient = any(
                code in error_str for code in ("503", "429", "UNAVAILABLE", "RESOURCE_EXHAUSTED")
            )
            if not is_transient or attempt == max_retries:
                raise
            delay = base_delay * (2 ** attempt) + random.uniform(0, 1)
            print(
                f"Gemini API transient error ({tier_label}, attempt {attempt + 1}/{max_retries}): "
                f"{e}. Retrying in {delay:.1f}s..."
            )
            await asyncio.sleep(delay)
    raise RuntimeError("Unreachable")


async def _generate_single_async(
    client: genai.Client,
    model: str,
    prompt: str,
    tier_label: str,
    target_words: list[str] | None = None,
) -> dict:
    """Gemini API で1文を非同期生成し NLP 後処理を適用する（バッチ並列用）。"""
    sentence: dict = {}
    current_prompt = prompt
    for attempt in range(1 + MAX_RETRY):
        result = await _call_gemini_with_retry(client, model, current_prompt, tier_label)
        if result.usage_metadata:
            print(
                f"Gemini token usage ({tier_label}): "
                f"input={result.usage_metadata.prompt_token_count}, "
                f"output={result.usage_metadata.candidates_token_count}, "
                f"total={result.usage_metadata.total_token_count}"
            )
        text = result.text
        if not text or not text.strip():
            raise RuntimeError("Empty response from Gemini API")
        sentence = json.loads(text)
        enrich_with_nlp(sentence)

        missing = validate_target_words(sentence, target_words)
        if not missing:
            return sentence

        print(
            f"Target word validation failed (attempt {attempt + 1}): "
            f"missing={missing}"
        )

        # リトライ時は不足単語を明示したプロンプトに差し替え
        missing_str = ", ".join(missing)
        current_prompt = (
            f"{prompt}\n\n"
            f"【再生成指示】前回の生成では次の単語が含まれていませんでした: {missing_str}\n"
            f"これらの単語を必ず文中に含めてください。"
        )

    # リトライ上限到達 — 生成自体は成功しているのでそのまま返す
    print(f"Returning sentence despite missing target words after {1 + MAX_RETRY} attempts")
    return sentence


def generate_sentence(
    params: dict,
    is_premium: bool,
    *,
    target_words: list[str] | None = None,
    estimated_vocab: int = 0,
) -> dict:
    """Gemini APIで例文を生成し、NLP後処理を適用する。"""
    api_key = get_gemini_api_key()
    client = genai.Client(api_key=api_key)
    model = GEMINI_MODEL_PREMIUM if is_premium else GEMINI_MODEL
    tier_label = "premium" if is_premium else "free"
    prompt = build_uvm_prompt(
        params, target_words, estimated_vocab=estimated_vocab, is_premium=is_premium
    )
    return _generate_single(client, model, prompt, tier_label, target_words)


async def _generate_batch_async(
    count: int,
    is_premium: bool,
    *,
    all_target_words: list[list[str]],
    all_topics: list[str],
    estimated_vocab: int = 0,
) -> list[dict]:
    """複数の例文を asyncio.gather で並列生成する。"""
    api_key = get_gemini_api_key()
    client = genai.Client(api_key=api_key)
    model = GEMINI_MODEL_PREMIUM if is_premium else GEMINI_MODEL
    tier_label = "premium" if is_premium else "free"

    tasks = []
    for i in range(count):
        tw = all_target_words[i] if i < len(all_target_words) else None
        topic = all_topics[i] if i < len(all_topics) else ""
        prompt = build_uvm_prompt(
            {"topic": topic} if topic else {},
            tw,
            estimated_vocab=estimated_vocab,
            is_premium=is_premium,
        )
        tasks.append(_generate_single_async(client, model, prompt, tier_label, tw))

    results = await asyncio.gather(*tasks, return_exceptions=True)

    sentences: list[dict] = []
    for idx, r in enumerate(results):
        if isinstance(r, BaseException):
            print(f"Batch generation failed for index {idx}: {r}")
        else:
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
    """複数の例文を並列で生成する（sync ラッパー）。

    Args:
        count: 生成する例文数
        is_premium: プレミアムティアか
        all_target_words: 各例文用のターゲット単語リスト（len == count）
        all_topics: 各例文用のトピック（len == count）
        estimated_vocab: ユーザーの推定語彙数

    Returns:
        成功した例文のリスト
    """
    return asyncio.run(
        _generate_batch_async(
            count,
            is_premium,
            all_target_words=all_target_words,
            all_topics=all_topics,
            estimated_vocab=estimated_vocab,
        )
    )
