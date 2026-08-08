"""LLM プロバイダー抽象レイヤ。

`SENTENCE_PROVIDER` 定数で OpenAI / Gemini を切り替える。
提供する関数は 2 つだけ:

  - generate_sentence_sync(system_prompt, user_prompt, is_premium, tier_label) -> dict
  - generate_sentence_async(system_prompt, user_prompt, is_premium, tier_label) -> dict

system_prompt は呼び出しごとに変化しない固定テキスト（prefix キャッシュ用）。
OpenAI は instructions、Gemini は system_instruction として渡す。
どちらも RESPONSE_JSON_SCHEMA 準拠の dict を返す（NLP 後処理は呼び出し側で実施）。
"""

import asyncio
import json
import os
import random
import time
import urllib.error
import urllib.request
from dataclasses import dataclass
from types import SimpleNamespace
from typing import Any

from google.cloud import secretmanager

try:
    from .constants import (
        API_MAX_TOKENS,
        GEMINI_MODEL,
        GEMINI_MODEL_PREMIUM,
        OPENAI_MODEL,
        OPENAI_MODEL_PREMIUM,
        RESPONSE_JSON_SCHEMA,
        SENTENCE_PROVIDER,
    )
except ImportError:
    from constants import (
        API_MAX_TOKENS,
        GEMINI_MODEL,
        GEMINI_MODEL_PREMIUM,
        OPENAI_MODEL,
        OPENAI_MODEL_PREMIUM,
        RESPONSE_JSON_SCHEMA,
        SENTENCE_PROVIDER,
    )


# ─── 共通ユーティリティ ───


_API_KEY_TTL_SECONDS: float = 3600.0
_TRANSIENT_STATUS = {408, 429, 500, 502, 503, 504}


@dataclass
class LLMApiError(Exception):
    status_code: int | None
    message: str
    provider: str

    @property
    def is_transient(self) -> bool:
        return self.status_code is None or self.status_code in _TRANSIENT_STATUS

    def __str__(self) -> str:
        status = self.status_code if self.status_code is not None else "network"
        return f"{self.provider} API error status={status}: {self.message}"


def _get_secret(secret_id: str) -> str:
    project_id = os.environ.get("GCLOUD_PROJECT", "")
    client = secretmanager.SecretManagerServiceClient()
    name = f"projects/{project_id}/secrets/{secret_id}/versions/latest"
    response = client.access_secret_version(request={"name": name})
    value = response.payload.data.decode("UTF-8")
    if not value:
        raise RuntimeError("SECRET_MANAGER_ERROR")
    return value


# ─── OpenAI プロバイダー ───


_OPENAI_RESPONSES_URL = "https://api.openai.com/v1/responses"
_GEMINI_API_BASE = "https://generativelanguage.googleapis.com/v1beta"
_openai_api_key: str | None = None
_openai_api_key_fetched_at: float = 0.0


OPENAI_TOKEN_PRICING_PER_MILLION: dict[str, dict[str, float]] = {
    "gpt-5.6-luna": {"input": 0.20, "cached_input": 0.02, "output": 1.20},
    "gpt-5.4-mini": {"input": 0.75, "cached_input": 0.075, "output": 4.50},
    "gpt-5.4-nano": {"input": 0.20, "cached_input": 0.02, "output": 1.25},
    "gpt-5-mini": {"input": 0.25, "cached_input": 0.025, "output": 2.00},
    "gpt-5-nano": {"input": 0.05, "cached_input": 0.005, "output": 0.40},
}
_DEFAULT_OPENAI_PRICING = OPENAI_TOKEN_PRICING_PER_MILLION["gpt-5.4-nano"]


def _get_openai_api_key() -> str:
    global _openai_api_key, _openai_api_key_fetched_at
    if (
        _openai_api_key is not None
        and (time.monotonic() - _openai_api_key_fetched_at) < _API_KEY_TTL_SECONDS
    ):
        return _openai_api_key

    env_key = os.environ.get("OPENAI_API_KEY", "").strip()
    if env_key:
        _openai_api_key = env_key
        _openai_api_key_fetched_at = time.monotonic()
        return env_key

    api_key = _get_secret("openai-api-key")
    _openai_api_key = api_key
    _openai_api_key_fetched_at = time.monotonic()
    return api_key


def _openai_reasoning_effort(model: str, is_premium: bool = False) -> str:
    # 検証時に効きを比べられるよう環境変数で上書き可（none/low/medium/high）。
    override = os.environ.get("OPENAI_REASONING_EFFORT")
    if override:
        return override
    # free/premium とも medium。high はレイテンシが暴れる（2026-08-05 実測、
    # gpt-5.6-luna・20文並列: high 中央値10.5秒/p90 37秒/最大77秒、
    # medium 中央値6.0秒/p90 9.3秒/最大16.4秒）。high は 28件中1件が74秒かけて
    # empty output になり、リトライでさらに倍のレイテンシになる。
    # 品質は medium でも文体遵守・訳文・多義語の使い分けが維持されることを確認済み
    # （落ちるのは none。none では ถูก が全て「安い」になる）。
    if model.startswith("gpt-5"):
        return "medium"
    return "none"


def _openai_payload(
    model: str,
    system_prompt: str,
    user_prompt: str,
    is_premium: bool = False,
    schema: dict[str, Any] | None = None,
) -> dict[str, Any]:
    return {
        "model": model,
        "instructions": system_prompt,
        "input": [{"role": "user", "content": user_prompt}],
        "max_output_tokens": API_MAX_TOKENS,
        "reasoning": {"effort": _openai_reasoning_effort(model, is_premium)},
        "text": {
            "format": {
                "type": "json_schema",
                "name": "thai_sentence_response",
                "strict": True,
                "schema": schema if schema is not None else RESPONSE_JSON_SCHEMA,
            },
        },
    }


def _openai_extract_text(response_body: dict[str, Any]) -> str | None:
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
                if isinstance(content_item, dict) and isinstance(
                    content_item.get("text"), str
                ):
                    parts.append(content_item["text"])

    text = "".join(parts).strip()
    return text or None


def _openai_log_token_usage(
    usage: dict[str, Any] | None, tier_label: str, model: str
) -> None:
    if not usage:
        return

    input_tokens = int(usage.get("input_tokens") or 0)
    output_tokens = int(usage.get("output_tokens") or 0)
    input_details = usage.get("input_tokens_details")
    cached_tokens = (
        int(input_details.get("cached_tokens") or 0)
        if isinstance(input_details, dict)
        else 0
    )
    output_details = usage.get("output_tokens_details")
    reasoning_tokens = (
        int(output_details.get("reasoning_tokens") or 0)
        if isinstance(output_details, dict)
        else 0
    )
    total_tokens = int(usage.get("total_tokens") or input_tokens + output_tokens)
    pricing = OPENAI_TOKEN_PRICING_PER_MILLION.get(model, _DEFAULT_OPENAI_PRICING)
    cached_input_price = pricing.get("cached_input", pricing["input"] * 0.1)
    uncached_input_tokens = max(input_tokens - cached_tokens, 0)
    cost_usd = (
        uncached_input_tokens * pricing["input"]
        + cached_tokens * cached_input_price
        + output_tokens * pricing["output"]
    ) / 1_000_000

    print(
        f"OpenAI token usage ({tier_label}): "
        f"model={model}, input={input_tokens} (cached={cached_tokens}), "
        f"output={output_tokens}, reasoning={reasoning_tokens}, "
        f"total={total_tokens}, cost=${cost_usd:.6f}"
    )


def _read_http_error_body(error: urllib.error.HTTPError) -> dict[str, Any]:
    body = error.read().decode("utf-8", errors="replace")
    try:
        parsed = json.loads(body)
        return parsed if isinstance(parsed, dict) else {}
    except json.JSONDecodeError:
        return {"error": {"message": body}}


def _openai_post(api_key: str, payload: dict[str, Any]) -> dict[str, Any]:
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
        raw_error = body.get("error")
        error = raw_error if isinstance(raw_error, dict) else {}
        raise LLMApiError(
            status_code=exc.code,
            message=str(error.get("message") or "Request failed"),
            provider="OpenAI",
        ) from exc
    except (TimeoutError, urllib.error.URLError) as exc:
        raise LLMApiError(
            status_code=None, message=str(exc), provider="OpenAI"
        ) from exc

    try:
        parsed = json.loads(response_body)
    except json.JSONDecodeError as exc:
        raise RuntimeError("LLM_API_ERROR: invalid JSON response") from exc

    if not isinstance(parsed, dict):
        raise RuntimeError("LLM_API_ERROR: unexpected response shape")
    return parsed


def _openai_generate_sync(
    system_prompt: str,
    user_prompt: str,
    is_premium: bool,
    tier_label: str,
    schema: dict[str, Any] | None = None,
) -> dict[str, Any]:
    api_key = _get_openai_api_key()
    model = OPENAI_MODEL_PREMIUM if is_premium else OPENAI_MODEL
    payload = _openai_payload(model, system_prompt, user_prompt, is_premium, schema)

    response_body = _call_with_retry(
        lambda: _openai_post(api_key, payload),
        tier_label=tier_label,
        provider_label="OpenAI",
    )

    _openai_log_token_usage(response_body.get("usage"), tier_label, model)
    text = _openai_extract_text(response_body)
    if not text:
        raise RuntimeError("LLM_API_ERROR: empty output")
    return _parse_json_text(text)


# ─── Gemini プロバイダー ───


_gemini_api_key: str | None = None
_gemini_api_key_fetched_at: float = 0.0


# Gemini 2.5 Flash の価格（1M トークンあたり USD）
# https://ai.google.dev/pricing
GEMINI_TOKEN_PRICING_PER_MILLION: dict[str, dict[str, float]] = {
    "gemini-2.5-flash": {"input": 0.30, "output": 2.50},
    "gemini-2.5-flash-lite": {"input": 0.10, "output": 0.40},
    "gemini-2.5-pro": {"input": 1.25, "output": 10.00},
    "gemini-3.1-flash-lite": {"input": 0.25, "output": 1.50},
    "gemini-3-flash": {"input": 0.50, "output": 3.00},
    "gemini-3.5-flash": {"input": 1.50, "output": 9.00},
}
_DEFAULT_GEMINI_PRICING = GEMINI_TOKEN_PRICING_PER_MILLION["gemini-3.1-flash-lite"]


def _get_gemini_api_key() -> str:
    global _gemini_api_key, _gemini_api_key_fetched_at
    if (
        _gemini_api_key is not None
        and (time.monotonic() - _gemini_api_key_fetched_at) < _API_KEY_TTL_SECONDS
    ):
        return _gemini_api_key

    env_key = os.environ.get("GEMINI_API_KEY", "").strip()
    if env_key:
        _gemini_api_key = env_key
        _gemini_api_key_fetched_at = time.monotonic()
        return env_key

    api_key = _get_secret("gemini-api-key")
    _gemini_api_key = api_key
    _gemini_api_key_fetched_at = time.monotonic()
    return api_key


def _gemini_schema(schema: dict[str, Any] | None = None) -> dict[str, Any]:
    """Gemini 用にレスポンススキーマを変換する。

    Gemini は additionalProperties を受け付けないため取り除く。
    """

    def strip(node: Any) -> Any:
        if isinstance(node, dict):
            return {k: strip(v) for k, v in node.items() if k != "additionalProperties"}
        if isinstance(node, list):
            return [strip(v) for v in node]
        return node

    return strip(schema if schema is not None else RESPONSE_JSON_SCHEMA)


def _gemini_log_token_usage(
    usage_metadata: Any, tier_label: str, model: str
) -> None:
    if usage_metadata is None:
        return

    def _get(name: str) -> int:
        value = getattr(usage_metadata, name, None)
        return int(value) if value is not None else 0

    prompt_tokens = _get("prompt_token_count")
    output_tokens = _get("candidates_token_count")
    thoughts_tokens = _get("thoughts_token_count")
    billed_output_tokens = output_tokens + thoughts_tokens
    total_tokens = _get("total_token_count") or prompt_tokens + billed_output_tokens
    pricing = GEMINI_TOKEN_PRICING_PER_MILLION.get(model, _DEFAULT_GEMINI_PRICING)
    cost_usd = (
        prompt_tokens * pricing["input"]
        + billed_output_tokens * pricing["output"]
    ) / 1_000_000

    print(
        f"Gemini token usage ({tier_label}): "
        f"model={model}, input={prompt_tokens}, "
        f"output={output_tokens}, thoughts={thoughts_tokens}, "
        f"billed_output={billed_output_tokens}, "
        f"total={total_tokens}, cost=${cost_usd:.6f}"
    )


def _gemini_response(body: dict[str, Any]) -> Any:
    """REST レスポンスを google-genai 互換の形（.text / .usage_metadata）に包む。

    呼び出し側（_gemini_generate_sync / _gemini_log_token_usage）が
    SDK のオブジェクトを前提にしているため、属性名を snake_case で合わせる。
    """
    parts: list[str] = []
    for candidate in body.get("candidates") or []:
        for part in (candidate.get("content") or {}).get("parts") or []:
            text = part.get("text")
            if isinstance(text, str):
                parts.append(text)

    raw_usage = body.get("usageMetadata") or {}
    usage = SimpleNamespace(
        prompt_token_count=raw_usage.get("promptTokenCount"),
        candidates_token_count=raw_usage.get("candidatesTokenCount"),
        thoughts_token_count=raw_usage.get("thoughtsTokenCount"),
        total_token_count=raw_usage.get("totalTokenCount"),
    )
    return SimpleNamespace(text="".join(parts), usage_metadata=usage)


def _gemini_call(
    model: str,
    system_prompt: str,
    user_prompt: str,
    is_premium: bool,
    schema: dict[str, Any] | None = None,
) -> Any:
    """Gemini generateContent を REST で同期呼び出しする。

    google-genai SDK は使わない。SDK の import は aiohttp / pydantic まで
    引き連れており、Cloud Run のイメージ遅延ロードと相まってコールドスタート時に
    実測9秒かかっていた（2026-07-31 dev計測）。OpenAI 側と同じく urllib で叩く。
    例外は LLMApiError に正規化する。
    """
    payload: dict[str, Any] = {
        "contents": [{"role": "user", "parts": [{"text": user_prompt}]}],
        "systemInstruction": {"parts": [{"text": system_prompt}]},
        "generationConfig": {
            "responseMimeType": "application/json",
            "responseSchema": _gemini_schema(schema),
            "maxOutputTokens": API_MAX_TOKENS,
            "thinkingConfig": {"thinkingBudget": 1024 if is_premium else 256},
        },
    }
    request = urllib.request.Request(
        f"{_GEMINI_API_BASE}/models/{model}:generateContent",
        data=json.dumps(payload).encode("utf-8"),
        headers={
            "x-goog-api-key": _get_gemini_api_key(),
            "Content-Type": "application/json",
        },
        method="POST",
    )

    try:
        with urllib.request.urlopen(request, timeout=90) as response:
            response_body = response.read().decode("utf-8")
    except urllib.error.HTTPError as exc:
        body = _read_http_error_body(exc)
        raw_error = body.get("error")
        error = raw_error if isinstance(raw_error, dict) else {}
        raise LLMApiError(
            status_code=exc.code,
            message=str(error.get("message") or "Request failed"),
            provider="Gemini",
        ) from exc
    except (TimeoutError, urllib.error.URLError) as exc:
        raise LLMApiError(
            status_code=None, message=str(exc), provider="Gemini"
        ) from exc

    try:
        parsed = json.loads(response_body)
    except json.JSONDecodeError as exc:
        raise RuntimeError("LLM_API_ERROR: invalid JSON response") from exc

    if not isinstance(parsed, dict):
        raise RuntimeError("LLM_API_ERROR: unexpected response shape")
    return _gemini_response(parsed)


def _gemini_generate_sync(
    system_prompt: str,
    user_prompt: str,
    is_premium: bool,
    tier_label: str,
    schema: dict[str, Any] | None = None,
) -> dict[str, Any]:
    model = GEMINI_MODEL_PREMIUM if is_premium else GEMINI_MODEL
    response = _call_with_retry(
        lambda: _gemini_call(model, system_prompt, user_prompt, is_premium, schema),
        tier_label=tier_label,
        provider_label="Gemini",
    )

    _gemini_log_token_usage(
        getattr(response, "usage_metadata", None), tier_label, model
    )
    text = getattr(response, "text", None)
    if not isinstance(text, str) or not text.strip():
        raise RuntimeError("LLM_API_ERROR: empty output")
    return _parse_json_text(text)


# ─── 共通呼び出しフロー ───


def _parse_json_text(text: str) -> dict[str, Any]:
    try:
        parsed = json.loads(text)
    except json.JSONDecodeError as exc:
        raise RuntimeError("LLM_API_ERROR: invalid structured output") from exc
    if not isinstance(parsed, dict):
        raise RuntimeError("LLM_API_ERROR: unexpected structured output")
    return parsed


def _call_with_retry(
    call: Any,
    *,
    tier_label: str,
    provider_label: str,
    max_retries: int = 3,
    base_delay: float = 2.0,
) -> Any:
    for attempt in range(1 + max_retries):
        try:
            return call()
        except LLMApiError as exc:
            if not exc.is_transient or attempt == max_retries:
                raise RuntimeError(f"LLM_API_ERROR: {exc}") from exc
            delay = base_delay * (2**attempt) + random.uniform(0, 1)
            print(
                f"{provider_label} API transient error "
                f"({tier_label}, attempt {attempt + 1}/{max_retries}): "
                f"{exc}. Retrying in {delay:.1f}s..."
            )
            time.sleep(delay)
    raise RuntimeError("Unreachable")


def generate_sentence_sync(
    system_prompt: str,
    user_prompt: str,
    is_premium: bool,
    tier_label: str,
    schema: dict[str, Any] | None = None,
) -> dict[str, Any]:
    """設定されたプロバイダーで同期的に例文を生成し、構造化 dict を返す。
    free/premium とも SENTENCE_PROVIDER のプロバイダーを使う。
    モデル名は OPENAI_MODEL* / GEMINI_MODEL* 環境変数で上書き可。
    schema を省略すると RESPONSE_JSON_SCHEMA を使う。
    """
    # free ティアは常に Gemini。premium は SENTENCE_PROVIDER に従う。
    # 2026-08-05 に free も OpenAI へ寄せたが、同日この形へ差し戻した。
    if not is_premium or SENTENCE_PROVIDER == "gemini":
        return _gemini_generate_sync(
            system_prompt, user_prompt, is_premium, tier_label, schema
        )
    return _openai_generate_sync(
        system_prompt, user_prompt, is_premium, tier_label, schema
    )


async def generate_sentence_async(
    system_prompt: str,
    user_prompt: str,
    is_premium: bool,
    tier_label: str,
    schema: dict[str, Any] | None = None,
) -> dict[str, Any]:
    """同期版を別スレッドで実行する非同期ラッパー。"""
    return await asyncio.to_thread(
        generate_sentence_sync,
        system_prompt,
        user_prompt,
        is_premium,
        tier_label,
        schema,
    )
