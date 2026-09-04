"""prod GA4 のカスタム定義をコード上の計測スキーマと同期する。

何も付けずに実行すると差分だけを表示し、GA4 は変更しない。

usage:
  uv run python scripts/ga4_register_dimension.py          # plan
  uv run python scripts/ga4_register_dimension.py --check  # 差分があれば exit 1
  uv run python scripts/ga4_register_dimension.py --apply  # 不足分を登録
  uv run python scripts/ga4_register_dimension.py --list   # 現在値を表示

登録は遡及しない。既存定義は履歴を壊さないため自動で archive しない。
"""

from __future__ import annotations

import json
import subprocess
import sys
from dataclasses import dataclass

PROP = "534357716"
SA = "ga4-analytics@thai-memo-prod.iam.gserviceaccount.com"
PROPERTY_BASE = f"https://analyticsadmin.googleapis.com/v1beta/properties/{PROP}"


@dataclass(frozen=True)
class Dimension:
    parameter: str
    scope: str
    display_name: str
    description: str = ""


@dataclass(frozen=True)
class Metric:
    parameter: str
    display_name: str
    description: str = ""


# lib/services/analytics_service.dart でレポートに使う文字列パラメータ。
DIMENSIONS = (
    Dimension("source", "EVENT", "Event source"),
    Dimension("action", "EVENT", "Event action"),
    Dimension("tier", "EVENT", "Event tier"),
    Dimension("topic", "EVENT", "Sentence topic"),
    Dimension("content_type", "EVENT", "TTS content type"),
    Dimension("category", "EVENT", "Quiz category"),
    Dimension("correct", "EVENT", "Quiz answer correct"),
    Dimension("is_premium", "EVENT", "Premium at event"),
    Dimension("monotone", "EVENT", "Pronunciation monotone"),
    Dimension("worst_tone", "EVENT", "Worst pronunciation tone"),
    Dimension("product_loaded", "EVENT", "Paywall product loaded"),
    Dimension("status", "EVENT", "Purchase result status"),
    Dimension("code", "EVENT", "Purchase diagnostic code"),
    Dimension("ok", "EVENT", "Purchase verification result"),
    Dimension("value", "EVENT", "Event value"),
    Dimension("key", "EVENT", "Setting key"),
    Dimension("coach_id", "EVENT", "Coach mark ID"),
    Dimension("question", "EVENT", "Interview question"),
    Dimension("answer", "EVENT", "Interview answer"),
    Dimension("outcome", "EVENT", "Review prompt outcome"),
    Dimension("lang", "EVENT", "Resolved app language"),
    Dimension("storefront", "EVENT", "App Store storefront"),
    Dimension("tier", "USER", "User tier"),
    Dimension("app_language", "USER", "User app language"),
)


# 数値として合計・平均を取るパラメータ。boolean は上の文字列dimensionを使う。
METRICS = (
    Metric("count", "Generated sentence count"),
    Metric("question_count", "Quiz question count"),
    Metric("vocab", "Estimated vocabulary"),
    Metric("pronunciation_score", "Pronunciation score"),
    Metric("syllable_count", "Pronunciation syllable count"),
    Metric("recognized_pct", "Recognized syllable percent"),
    Metric("quiz_score", "Summary quiz score"),
    Metric("vocab_before", "Vocabulary before quiz"),
    Metric("vocab_after", "Vocabulary after quiz"),
)


def token() -> str:
    result = subprocess.run(
        [
            "gcloud",
            "auth",
            "print-access-token",
            f"--impersonate-service-account={SA}",
            "--scopes=https://www.googleapis.com/auth/analytics.edit",
        ],
        capture_output=True,
        text=True,
        check=False,
    )
    value = result.stdout.strip()
    if result.returncode != 0 or len(value) < 50:
        raise SystemExit(f"token error: {result.stderr[:300]}")
    return value


def request(access_token: str, url: str, body: dict | None = None) -> dict:
    command = ["curl", "-sS", "-H", f"Authorization: Bearer {access_token}"]
    if body is not None:
        command += ["-H", "Content-Type: application/json", "-d", json.dumps(body)]
    command.append(url)
    result = subprocess.run(command, capture_output=True, text=True, check=False)
    if result.returncode != 0:
        raise SystemExit(f"request error: {result.stderr[:300]}")
    try:
        response = json.loads(result.stdout)
    except json.JSONDecodeError:
        raise SystemExit(f"invalid response: {result.stdout[:300]}") from None
    if "error" in response:
        raise SystemExit(f"GA4 error: {response['error'].get('message')}")
    return response


def current(access_token: str) -> tuple[list[dict], list[dict]]:
    dimensions = request(
        access_token, f"{PROPERTY_BASE}/customDimensions?pageSize=200"
    ).get("customDimensions", [])
    metrics = request(
        access_token, f"{PROPERTY_BASE}/customMetrics?pageSize=200"
    ).get("customMetrics", [])
    return dimensions, metrics


def missing_definitions(
    dimensions: list[dict], metrics: list[dict]
) -> tuple[list[Dimension], list[Metric]]:
    existing_dimensions = {
        (item["parameterName"], item["scope"]) for item in dimensions
    }
    existing_metrics = {item["parameterName"] for item in metrics}
    return (
        [d for d in DIMENSIONS if (d.parameter, d.scope) not in existing_dimensions],
        [m for m in METRICS if m.parameter not in existing_metrics],
    )


def print_current(dimensions: list[dict], metrics: list[dict]) -> None:
    print("custom dimensions:")
    for item in dimensions:
        print(f"  {item['scope']:<5} {item['parameterName']:<24} {item['displayName']}")
    print("custom metrics:")
    for item in metrics:
        print(f"  EVENT {item['parameterName']:<24} {item['displayName']}")


def print_plan(dimensions: list[Dimension], metrics: list[Metric]) -> None:
    if not dimensions and not metrics:
        print("GA4 custom definitions are in sync.")
        return
    print("missing custom definitions:")
    for item in dimensions:
        print(f"  + dimension {item.scope:<5} {item.parameter}")
    for item in metrics:
        print(f"  + metric    EVENT {item.parameter}")


def apply(access_token: str, dimensions: list[Dimension], metrics: list[Metric]) -> None:
    for item in dimensions:
        body = {
            "parameterName": item.parameter,
            "displayName": item.display_name,
            "scope": item.scope,
        }
        if item.description:
            body["description"] = item.description
        request(access_token, f"{PROPERTY_BASE}/customDimensions", body)
        print(f"registered dimension: {item.scope} {item.parameter}")
    for item in metrics:
        body = {
            "parameterName": item.parameter,
            "displayName": item.display_name,
            "scope": "EVENT",
            "measurementUnit": "STANDARD",
        }
        if item.description:
            body["description"] = item.description
        request(access_token, f"{PROPERTY_BASE}/customMetrics", body)
        print(f"registered metric: EVENT {item.parameter}")


def main() -> None:
    mode = sys.argv[1] if len(sys.argv) > 1 else "--plan"
    if mode not in {"--plan", "--check", "--apply", "--list"}:
        raise SystemExit("usage: ga4_register_dimension.py [--plan|--check|--apply|--list]")
    access_token = token()
    dimensions, metrics = current(access_token)
    if mode == "--list":
        print_current(dimensions, metrics)
        return
    missing_dimensions, missing_metrics = missing_definitions(dimensions, metrics)
    print_plan(missing_dimensions, missing_metrics)
    if mode == "--check" and (missing_dimensions or missing_metrics):
        raise SystemExit(1)
    if mode == "--apply":
        apply(access_token, missing_dimensions, missing_metrics)


if __name__ == "__main__":
    main()
