import json
import os

from google import genai
from google.cloud import secretmanager
from google.cloud import storage as gcs
from google.cloud.firestore_v1.client import Client as FirestoreClient

from constants import (
    API_MAX_TOKENS,
    API_TEMPERATURE,
    GEMINI_MODEL,
    GEMINI_MODEL_PREMIUM,
    RESPONSE_SCHEMA,
)
from nlp import enrich_with_nlp
from prompts import build_uvm_prompt
from uvm import get_session_words

_freq_rank: dict[str, int] | None = None


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
    client = secretmanager.SecretManagerServiceClient()
    project_id = os.environ.get("GCLOUD_PROJECT", "")
    name = f"projects/{project_id}/secrets/gemini-api-key/versions/latest"
    response = client.access_secret_version(request={"name": name})
    api_key = response.payload.data.decode("UTF-8")
    if not api_key:
        raise RuntimeError("SECRET_MANAGER_ERROR")
    return api_key


def select_uvm_target_words(
    db: FirestoreClient,
    uid: str,
    params: dict,
    api_key: str | None = None,
    max_vocab: int | None = None,
) -> list[str]:
    """UVMから例文生成用のターゲット単語を選定する。

    Args:
        max_vocab: 語彙帯域の上限。free ティアでは 300 に制限。
    """
    freq_rank = get_freq_rank()
    topic = params.get("topic", "")
    return get_session_words(
        db, uid, freq_rank, topic=topic, count=1, api_key=api_key,
        max_vocab=max_vocab,
    )


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
    prompt = build_uvm_prompt(params, target_words, estimated_vocab=estimated_vocab, is_premium=is_premium)

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
    return sentence
