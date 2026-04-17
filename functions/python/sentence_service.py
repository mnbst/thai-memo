import asyncio
import json
import os
import random
import time
import urllib.error
import urllib.request
from dataclasses import dataclass
from typing import Any

from google.cloud import secretmanager
from google.cloud import storage as gcs
from google.cloud.firestore_v1.client import Client as FirestoreClient

from constants import (
    API_MAX_TOKENS,
    FREE_TOPICS,
    OPENAI_MODEL,
    OPENAI_MODEL_PREMIUM,
    RESPONSE_JSON_SCHEMA,
    TOPICS,
)
from nlp import enrich_with_nlp
from prompts import build_uvm_prompt
from uvm import get_session_words

_freq_rank: dict[str, int] | None = None
_openai_api_key: str | None = None
_openai_api_key_fetched_at: float = 0.0
_OPENAI_KEY_TTL_SECONDS: float = 3600.0  # 1時間
_OPENAI_RESPONSES_URL = "https://api.openai.com/v1/responses"


@dataclass
class OpenAiApiError(Exception):
    status_code: int | None
    message: str
    error_type: str | None = None
    error_code: str | None = None

    @property
    def is_transient(self) -> bool:
        return self.status_code is None or self.status_code in {429, 500, 502, 503, 504}

    def __str__(self) -> str:
        status = self.status_code if self.status_code is not None else "network"
        detail = f"OpenAI API error status={status}: {self.message}"
        if self.error_type:
            detail += f" type={self.error_type}"
        if self.error_code:
            detail += f" code={self.error_code}"
        return detail


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


def get_openai_api_key() -> str:
    global _openai_api_key, _openai_api_key_fetched_at
    if (
        _openai_api_key is not None
        and (time.monotonic() - _openai_api_key_fetched_at) < _OPENAI_KEY_TTL_SECONDS
    ):
        return _openai_api_key

    env_key = os.environ.get("OPENAI_API_KEY", "").strip()
    if env_key:
        _openai_api_key = env_key
        _openai_api_key_fetched_at = time.monotonic()
        return env_key

    client = secretmanager.SecretManagerServiceClient()
    project_id = os.environ.get("GCLOUD_PROJECT", "")
    name = f"projects/{project_id}/secrets/openai-api-key/versions/latest"
    response = client.access_secret_version(request={"name": name})
    api_key = response.payload.data.decode("UTF-8")
    if not api_key:
        raise RuntimeError("SECRET_MANAGER_ERROR")
    _openai_api_key = api_key
    _openai_api_key_fetched_at = time.monotonic()
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
        estimated_vocab: 呼び出し元で取得済みの語彙スコア。省略時は Firestore から読む。

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


def _get_reasoning_effort(model: str) -> str:
    if model.startswith("gpt-5.4-") or model.startswith("gpt-5-"):
        return "low"
    return "none"


def _make_generation_payload(model: str, prompt: str) -> dict[str, Any]:
    """OpenAI Responses API に送る payload を返す。"""
    return {
        "model": model,
        "input": [
            {
                "role": "user",
                "content": prompt,
            }
        ],
        "max_output_tokens": API_MAX_TOKENS,
        "reasoning": {
            "effort": _get_reasoning_effort(model),
        },
        "text": {
            "format": {
                "type": "json_schema",
                "name": "thai_sentence_response",
                "strict": True,
                "schema": RESPONSE_JSON_SCHEMA,
            },
        },
    }


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


def _extract_output_text(response_body: dict[str, Any]) -> str | None:
    output_text = response_body.get("output_text")
    if isinstance(output_text, str) and output_text.strip():
        return output_text.strip()

    parts: list[str] = []
    output = response_body.get("output")
    if isinstance(output, list):
        for item in output:
            if not isinstance(item, dict):
                continue
            content = item.get("content")
            if not isinstance(content, list):
                continue
            for content_item in content:
                if (
                    isinstance(content_item, dict)
                    and isinstance(content_item.get("text"), str)
                ):
                    parts.append(content_item["text"])

    text = "".join(parts).strip()
    return text or None


OPENAI_TOKEN_PRICING_PER_MILLION: dict[str, dict[str, float]] = {
    "gpt-5.4-mini": {"input": 0.75, "output": 4.50},
    "gpt-5.4-nano": {"input": 0.20, "output": 1.25},
    "gpt-5-mini": {"input": 0.25, "output": 2.00},
    "gpt-5-nano": {"input": 0.05, "output": 0.40},
}
DEFAULT_OPENAI_TOKEN_PRICING_PER_MILLION = OPENAI_TOKEN_PRICING_PER_MILLION[
    "gpt-5.4-nano"
]


def _log_token_usage(usage: dict[str, Any] | None, tier_label: str, model: str) -> None:
    if not usage:
        return

    input_tokens = int(usage.get("input_tokens") or 0)
    output_tokens = int(usage.get("output_tokens") or 0)
    output_details = usage.get("output_tokens_details")
    reasoning_tokens = (
        int(output_details.get("reasoning_tokens") or 0)
        if isinstance(output_details, dict)
        else 0
    )
    total_tokens = int(usage.get("total_tokens") or input_tokens + output_tokens)
    pricing = OPENAI_TOKEN_PRICING_PER_MILLION.get(
        model,
        DEFAULT_OPENAI_TOKEN_PRICING_PER_MILLION,
    )
    cost_usd = (
        input_tokens * pricing["input"] + output_tokens * pricing["output"]
    ) / 1_000_000

    print(
        f"OpenAI token usage ({tier_label}): "
        f"model={model}, input={input_tokens}, output={output_tokens}, "
        f"reasoning={reasoning_tokens}, total={total_tokens}, "
        f"cost=${cost_usd:.6f}"
    )


def _read_http_error_body(error: urllib.error.HTTPError) -> dict[str, Any]:
    body = error.read().decode("utf-8", errors="replace")
    try:
        parsed = json.loads(body)
        return parsed if isinstance(parsed, dict) else {}
    except json.JSONDecodeError:
        return {"error": {"message": body}}


def _post_openai_response(api_key: str, payload: dict[str, Any]) -> dict[str, Any]:
    data = json.dumps(payload).encode("utf-8")
    request = urllib.request.Request(
        _OPENAI_RESPONSES_URL,
        data=data,
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        },
        method="POST",
    )

    try:
        with urllib.request.urlopen(request, timeout=90) as response:
            response_body = response.read().decode("utf-8")
    except urllib.error.HTTPError as exc:
        body = _read_http_error_body(exc)
        error = body.get("error") if isinstance(body.get("error"), dict) else {}
        raise OpenAiApiError(
            status_code=exc.code,
            message=str(error.get("message") or "Request failed"),
            error_type=error.get("type"),
            error_code=error.get("code"),
        ) from exc
    except (TimeoutError, urllib.error.URLError) as exc:
        raise OpenAiApiError(status_code=None, message=str(exc)) from exc

    try:
        parsed = json.loads(response_body)
    except json.JSONDecodeError as exc:
        raise RuntimeError("OPENAI_API_ERROR: invalid JSON response") from exc

    if not isinstance(parsed, dict):
        raise RuntimeError("OPENAI_API_ERROR: unexpected response shape")
    return parsed


def _call_openai_with_retry_sync(
    api_key: str,
    model: str,
    prompt: str,
    tier_label: str,
    *,
    max_retries: int = 3,
    base_delay: float = 2.0,
) -> dict[str, Any]:
    """OpenAI Responses API を同期呼び出しし、一時的エラー時はリトライする。"""
    payload = _make_generation_payload(model, prompt)
    for attempt in range(1 + max_retries):
        try:
            return _post_openai_response(api_key, payload)
        except OpenAiApiError as exc:
            if not exc.is_transient or attempt == max_retries:
                raise RuntimeError(f"OPENAI_API_ERROR: {exc}") from exc
            delay = base_delay * (2 ** attempt) + random.uniform(0, 1)
            print(
                f"OpenAI API transient error "
                f"({tier_label}, attempt {attempt + 1}/{max_retries}): "
                f"{exc}. Retrying in {delay:.1f}s..."
            )
            time.sleep(delay)
    raise RuntimeError("Unreachable")


async def _call_openai_with_retry(
    api_key: str,
    model: str,
    prompt: str,
    tier_label: str,
) -> dict[str, Any]:
    return await asyncio.to_thread(
        _call_openai_with_retry_sync,
        api_key,
        model,
        prompt,
        tier_label,
    )


def _parse_sentence_response(
    response_body: dict[str, Any],
    tier_label: str,
    model: str,
) -> dict:
    _log_token_usage(response_body.get("usage"), tier_label, model)
    text = _extract_output_text(response_body)
    if not text:
        raise RuntimeError("OPENAI_API_ERROR: empty output")
    try:
        sentence = json.loads(text)
    except json.JSONDecodeError as exc:
        raise RuntimeError("OPENAI_API_ERROR: invalid structured output") from exc
    if not isinstance(sentence, dict):
        raise RuntimeError("OPENAI_API_ERROR: unexpected structured output")
    enrich_with_nlp(sentence)
    return sentence


def _build_retry_prompt(prompt: str, missing: list[str]) -> str:
    missing_str = ", ".join(missing)
    return (
        f"{prompt}\n\n"
        f"【再生成指示】前回の生成では次の単語が含まれていませんでした: {missing_str}\n"
        f"これらの単語を必ず文中に含めてください。"
    )


def _generate_single(
    api_key: str,
    model: str,
    prompt: str,
    tier_label: str,
    target_words: list[str] | None = None,
) -> dict:
    """OpenAI で1文を同期生成し NLP 後処理を適用する。"""
    sentence: dict = {}
    current_prompt = prompt
    for attempt in range(1 + MAX_RETRY):
        result = _call_openai_with_retry_sync(api_key, model, current_prompt, tier_label)
        sentence = _parse_sentence_response(result, tier_label, model)

        missing = validate_target_words(sentence, target_words)
        if not missing:
            return sentence

        print(
            f"Target word validation failed (attempt {attempt + 1}): "
            f"missing={missing}"
        )
        current_prompt = _build_retry_prompt(prompt, missing)

    # リトライ上限到達 — 生成自体は成功しているのでそのまま返す
    print(
        f"Returning sentence despite missing target words after "
        f"{1 + MAX_RETRY} attempts"
    )
    return sentence


async def _generate_single_async(
    api_key: str,
    model: str,
    prompt: str,
    tier_label: str,
    target_words: list[str] | None = None,
) -> dict:
    """OpenAI で1文を非同期生成し NLP 後処理を適用する（バッチ並列用）。"""
    sentence: dict = {}
    current_prompt = prompt
    for attempt in range(1 + MAX_RETRY):
        result = await _call_openai_with_retry(api_key, model, current_prompt, tier_label)
        sentence = _parse_sentence_response(result, tier_label, model)

        missing = validate_target_words(sentence, target_words)
        if not missing:
            return sentence

        print(
            f"Target word validation failed (attempt {attempt + 1}): "
            f"missing={missing}"
        )
        current_prompt = _build_retry_prompt(prompt, missing)

    # リトライ上限到達 — 生成自体は成功しているのでそのまま返す
    print(
        f"Returning sentence despite missing target words after "
        f"{1 + MAX_RETRY} attempts"
    )
    return sentence


def generate_sentence(
    params: dict,
    is_premium: bool,
    *,
    target_words: list[str] | None = None,
    estimated_vocab: int = 0,
) -> dict:
    """OpenAI で例文を生成し、NLP後処理を適用する。"""
    api_key = get_openai_api_key()
    model = OPENAI_MODEL_PREMIUM if is_premium else OPENAI_MODEL
    tier_label = "premium" if is_premium else "free"
    prompt = build_uvm_prompt(
        params, target_words, estimated_vocab=estimated_vocab, is_premium=is_premium
    )
    return _generate_single(api_key, model, prompt, tier_label, target_words)


async def _generate_batch_async(
    count: int,
    is_premium: bool,
    *,
    all_target_words: list[list[str]],
    all_topics: list[str],
    estimated_vocab: int = 0,
) -> list[dict]:
    """複数の例文を asyncio.gather で並列生成する。"""
    api_key = get_openai_api_key()
    model = OPENAI_MODEL_PREMIUM if is_premium else OPENAI_MODEL
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
        tasks.append(_generate_single_async(api_key, model, prompt, tier_label, tw))

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
        estimated_vocab: ユーザーの語彙スコア

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
