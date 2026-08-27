"""llm_providers.py の純粋ロジックを Python 実装から書き出す。

Go 版 internal/llm との差分テストに使う。
本物の llm_providers をそのまま import して呼ぶので、移植のズレはテストが落ちる。
Secret Manager と urllib は import 前に差し替えて外へ出ないようにする。

出力先: functions/python/scripts/daily_golden/llm_golden.json
"""

import io
import json
import os
import random
import sys
import types
import urllib.error
from contextlib import redirect_stdout

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", ".."))

# google.cloud.secretmanager は import されるだけで良い（呼ばない）。
# 実物が入っていない環境でも動くようダミーを差しておく。
if "google.cloud.secretmanager" not in sys.modules:
    try:
        from google.cloud import secretmanager  # noqa: F401
    except Exception:  # pragma: no cover - 環境依存
        stub = types.ModuleType("google.cloud.secretmanager")
        stub.SecretManagerServiceClient = object
        sys.modules["google.cloud.secretmanager"] = stub

import llm_providers as lp  # noqa: E402

MODELS_OPENAI = [
    "gpt-5.6-luna", "gpt-5.4-mini", "gpt-5.4-nano",
    "gpt-5-mini", "gpt-5-nano", "gpt-4.1", "o3", "unknown-model",
]
MODELS_GEMINI = [
    "gemini-2.5-flash", "gemini-2.5-flash-lite", "gemini-2.5-pro",
    "gemini-3.1-flash-lite", "gemini-3.5-flash-lite", "gemini-3-flash",
    "gemini-3.5-flash", "gemini-9-ultra",
]
TIERS = ["free", "premium", "premium(trial)"]
# Python の strip() が落とす空白（Go の \s には入らないものを混ぜる）
SPACES = ["", " ", "  ", "\t", "\n", "　", " ", "\x1c", " "]


def capture(fn) -> str:
    buf = io.StringIO()
    with redirect_stdout(buf):
        fn()
    return buf.getvalue().rstrip("\n")


def rand_schema(rng: random.Random, depth: int = 0):
    """additionalProperties を散らした入れ子スキーマ。"""
    kind = rng.random()
    if depth >= 3 or kind < 0.3:
        return rng.choice(["string", 42, True, None, "integer"])
    if kind < 0.5:
        return [rand_schema(rng, depth + 1) for _ in range(rng.randint(0, 3))]
    node = {"type": "object", "properties": {}}
    if rng.random() < 0.6:
        node["additionalProperties"] = rng.choice([False, True, {"type": "string"}])
    for i in range(rng.randint(0, 3)):
        node["properties"][f"f{i}"] = rand_schema(rng, depth + 1)
    if rng.random() < 0.4:
        node["required"] = [f"f{i}" for i in range(rng.randint(0, 2))]
    return node


def rand_dict_schema(rng: random.Random) -> dict:
    """本番と同じく、最上位は必ず object のスキーマ。"""
    node = rand_schema(rng)
    if not isinstance(node, dict):
        node = {"type": "object", "properties": {"v": node}}
    return node


def main() -> None:
    rng = random.Random(20260828)
    out: dict = {}

    # --- LLMApiError: 文字列化と一過性判定 ---
    statuses = [None, 400, 401, 403, 404, 408, 409, 422, 429,
                499, 500, 502, 503, 504, 505, 200]
    out["errors"] = [
        {
            "status_code": s,
            "message": m,
            "provider": p,
            "str": str(lp.LLMApiError(status_code=s, message=m, provider=p)),
            "is_transient": lp.LLMApiError(
                status_code=s, message=m, provider=p
            ).is_transient,
        }
        for s in statuses
        for p in ("OpenAI", "Gemini")
        for m in ("Request failed", "rate limit reached", "")
    ]

    # --- _openai_reasoning_effort ---
    os.environ.pop("OPENAI_REASONING_EFFORT", None)
    effort = [
        {"model": m, "override": "", "effort": lp._openai_reasoning_effort(m)}
        for m in MODELS_OPENAI
    ]
    for override in ("none", "low", "medium", "high"):
        os.environ["OPENAI_REASONING_EFFORT"] = override
        effort += [
            {"model": m, "override": override,
             "effort": lp._openai_reasoning_effort(m)}
            for m in MODELS_OPENAI
        ]
    os.environ.pop("OPENAI_REASONING_EFFORT", None)
    out["reasoning_effort"] = effort

    # --- _openai_payload ---
    payloads = []
    for _ in range(300):
        model = rng.choice(MODELS_OPENAI)
        schema = rand_dict_schema(rng) if rng.random() < 0.7 else None
        system = "".join(rng.choice(SPACES + ["prompt", "指示", "ก"])
                         for _ in range(rng.randint(0, 8)))
        user = "".join(rng.choice(SPACES + ["ask", "文", "ข"])
                       for _ in range(rng.randint(0, 8)))
        payloads.append({
            "model": model,
            "system_prompt": system,
            "user_prompt": user,
            "schema": schema,
            "payload": lp._openai_payload(model, system, user, False, schema),
        })
    out["openai_payload"] = payloads
    out["api_max_tokens"] = lp.API_MAX_TOKENS
    out["response_json_schema"] = lp.RESPONSE_JSON_SCHEMA

    # --- _openai_extract_text ---
    def rand_text(rng):
        return "".join(rng.choice(SPACES + ["a", "{", "}", "あ"])
                       for _ in range(rng.randint(0, 6)))

    extracts = []
    for _ in range(600):
        body: dict = {}
        if rng.random() < 0.5:
            body["output_text"] = rng.choice(
                [rand_text(rng), "", "   ", 123, None, ["x"]])
        if rng.random() < 0.8:
            items = []
            for _ in range(rng.randint(0, 3)):
                if rng.random() < 0.15:
                    items.append(rng.choice(["not-a-dict", 5, None]))
                    continue
                item: dict = {}
                if rng.random() < 0.85:
                    contents = []
                    for _ in range(rng.randint(0, 3)):
                        r = rng.random()
                        if r < 0.15:
                            contents.append("bad")
                        elif r < 0.3:
                            contents.append({"text": rng.choice([1, None, []])})
                        else:
                            contents.append({"text": rand_text(rng)})
                    item["content"] = contents
                else:
                    item["content"] = rng.choice(["x", 3, None, {}])
                items.append(item)
            body["output"] = items
        elif rng.random() < 0.5:
            body["output"] = rng.choice(["x", 3, None, {}])
        extracts.append({"body": body, "text": lp._openai_extract_text(body)})
    out["openai_extract"] = extracts

    # --- _openai_log_token_usage ---
    usages = []
    for _ in range(600):
        if rng.random() < 0.06:
            usage = rng.choice([None, {}])
        else:
            usage = {}
            if rng.random() < 0.95:
                usage["input_tokens"] = rng.choice(
                    [0, 1, 7, 1234, 99999, None, rng.randint(0, 50000)])
            if rng.random() < 0.95:
                usage["output_tokens"] = rng.choice(
                    [0, 3, 512, None, rng.randint(0, 8192)])
            if rng.random() < 0.7:
                usage["input_tokens_details"] = rng.choice([
                    {"cached_tokens": rng.randint(0, 60000)},
                    {"cached_tokens": None},
                    {},
                    "nope",
                ])
            if rng.random() < 0.7:
                usage["output_tokens_details"] = rng.choice([
                    {"reasoning_tokens": rng.randint(0, 4000)},
                    {"reasoning_tokens": None},
                    {},
                    None,
                ])
            if rng.random() < 0.6:
                usage["total_tokens"] = rng.choice(
                    [0, None, rng.randint(0, 120000)])
        model = rng.choice(MODELS_OPENAI)
        tier = rng.choice(TIERS)
        line = capture(lambda: lp._openai_log_token_usage(usage, tier, model))
        usages.append({"usage": usage, "tier": tier, "model": model, "log": line})
    out["openai_usage_log"] = usages

    # --- _gemini_schema ---
    gem_schemas = []
    for _ in range(400):
        s = rand_schema(rng)
        while s is None:  # None は「未指定」で既定スキーマに化けるので除く
            s = rand_schema(rng)
        gem_schemas.append({"schema": s, "stripped": lp._gemini_schema(s)})
    out["gemini_schema"] = gem_schemas

    # --- _gemini_response（REST レスポンス → text / usage） ---
    responses = []
    for _ in range(500):
        body: dict = {}
        if rng.random() < 0.9:
            cands = []
            for _ in range(rng.randint(0, 3)):
                if rng.random() < 0.15:
                    cands.append({"content": rng.choice([None, {}, {"parts": None}])})
                    continue
                parts = []
                for _ in range(rng.randint(0, 3)):
                    if rng.random() < 0.2:
                        parts.append({"text": rng.choice([None, 5, []])})
                    else:
                        parts.append({"text": rand_text(rng)})
                cands.append({"content": {"parts": parts}})
            body["candidates"] = cands
        elif rng.random() < 0.5:
            body["candidates"] = None
        if rng.random() < 0.8:
            body["usageMetadata"] = {
                k: rng.choice([0, None, rng.randint(0, 50000)])
                for k in ("promptTokenCount", "candidatesTokenCount",
                          "thoughtsTokenCount", "totalTokenCount")
                if rng.random() < 0.85
            }
        resp = lp._gemini_response(body)
        u = resp.usage_metadata
        responses.append({
            "body": body,
            "text": resp.text,
            "usage": {
                "prompt": u.prompt_token_count,
                "candidates": u.candidates_token_count,
                "thoughts": u.thoughts_token_count,
                "total": u.total_token_count,
            },
        })
    out["gemini_response"] = responses

    # --- _gemini_log_token_usage ---
    gem_usages = []
    for case in responses[:400]:
        model = rng.choice(MODELS_GEMINI)
        tier = rng.choice(TIERS)
        resp = lp._gemini_response(case["body"])
        line = capture(
            lambda: lp._gemini_log_token_usage(resp.usage_metadata, tier, model))
        gem_usages.append({
            "usage": case["usage"], "tier": tier, "model": model, "log": line,
        })
    out["gemini_usage_log"] = gem_usages

    # --- _gemini_call が組み立てるリクエスト本文 ---
    calls = []
    captured: list = []

    class FakeResponse:
        def __init__(self, body: bytes):
            self._body = body

        def read(self):
            return self._body

        def __enter__(self):
            return self

        def __exit__(self, *args):
            return False

    def fake_urlopen(request, timeout=None):
        captured.append({
            "url": request.full_url,
            "body": json.loads(request.data.decode("utf-8")),
            "headers": dict(request.headers),
            "method": request.get_method(),
            "timeout": timeout,
        })
        return FakeResponse(b'{"candidates":[{"content":{"parts":[{"text":"{}"}]}}]}')

    real_urlopen = lp.urllib.request.urlopen
    lp.urllib.request.urlopen = fake_urlopen
    os.environ["GEMINI_API_KEY"] = "test-gemini-key"
    lp._gemini_api_key = None
    try:
        for _ in range(200):
            captured.clear()
            model = rng.choice(MODELS_GEMINI)
            is_premium = rng.random() < 0.5
            schema = rand_dict_schema(rng) if rng.random() < 0.7 else None
            budget = rng.choice([None, 0, 128, 4096])
            system = rand_text(rng)
            user = rand_text(rng)
            lp._gemini_call(model, system, user, is_premium, schema, budget)
            calls.append({
                "model": model,
                "is_premium": is_premium,
                "system_prompt": system,
                "user_prompt": user,
                "schema": schema,
                "thinking_budget": budget,
                "request": captured[0],
            })
    finally:
        lp.urllib.request.urlopen = real_urlopen
        os.environ.pop("GEMINI_API_KEY", None)
        lp._gemini_api_key = None
    out["gemini_request"] = calls

    # --- _read_http_error_body（エラー本文から message を取り出す） ---
    bodies = [
        b'{"error":{"message":"rate limit"}}',
        b'{"error":{"message":""}}',
        b'{"error":{"code":429}}',
        b'{"error":"flat string"}',
        b'{"error":null}',
        b'{}',
        b'[]',
        b'null',
        b'"just a string"',
        b'not json at all',
        b'',
        '{"error":{"message":"日本語"}}'.encode("utf-8"),
    ]
    err_cases = []
    for raw in bodies:
        exc = urllib.error.HTTPError(
            "https://x", 500, "err", {}, io.BytesIO(raw))
        parsed = lp._read_http_error_body(exc)
        raw_error = parsed.get("error")
        error = raw_error if isinstance(raw_error, dict) else {}
        err_cases.append({
            "raw": raw.decode("utf-8", errors="replace"),
            "message": str(error.get("message") or "Request failed"),
        })
    out["error_body"] = err_cases

    # --- _parse_json_text ---
    texts = [
        '{"a":1}', '  {"a":1}  ', '　{"a":1}', '[]', '"str"', '1', 'null',
        'true', '', '   ', '{', '{"a":', '{"a":1}{"b":2}', '{"あ":"い"}',
    ]
    parse_cases = []
    for t in texts:
        try:
            parse_cases.append({"text": t, "ok": True, "value": lp._parse_json_text(t)})
        except RuntimeError as exc:
            parse_cases.append({"text": t, "ok": False, "error": str(exc)})
    out["parse_json"] = parse_cases

    # --- _call_with_retry: 再送回数と最終メッセージ ---
    retry_cases = []
    real_sleep = lp.time.sleep
    lp.time.sleep = lambda _s: None
    try:
        for status in statuses + [None]:
            for fail_times in (0, 1, 3, 4, 99):
                calls_made = {"n": 0}

                def call():
                    calls_made["n"] += 1
                    if calls_made["n"] <= fail_times:
                        raise lp.LLMApiError(
                            status_code=status, message="boom", provider="OpenAI")
                    return {"ok": True}

                try:
                    with redirect_stdout(io.StringIO()):
                        lp._call_with_retry(
                            call, tier_label="free", provider_label="OpenAI")
                    result = {"ok": True}
                except RuntimeError as exc:
                    result = {"ok": False, "error": str(exc)}
                retry_cases.append({
                    "status_code": status,
                    "fail_times": fail_times,
                    "attempts": calls_made["n"],
                    **result,
                })
    finally:
        lp.time.sleep = real_sleep
    out["retry"] = retry_cases

    # --- バックオフの待ち時間（ジッタは外から与える） ---
    out["retry_delay"] = [
        {"attempt": a, "jitter": j, "seconds": 2.0 * (2 ** a) + j}
        for a in range(4)
        for j in (0.0, 0.25, 0.5, 0.999)
    ]

    path = os.path.join(os.path.dirname(__file__), "llm_golden.json")
    with open(path, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False)
    print("wrote", path)
    for k, v in out.items():
        if isinstance(v, list):
            print(f"  {k}: {len(v)}")


if __name__ == "__main__":
    main()
