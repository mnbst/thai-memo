import json
import os
import time
from datetime import datetime, timezone
from zoneinfo import ZoneInfo

from google import genai
from firebase_admin import firestore, initialize_app, messaging
from google.cloud.firestore_v1.base_document import DocumentSnapshot
from google.cloud.firestore_v1.client import Client as FirestoreClient
from firebase_functions import https_fn, scheduler_fn  # type: ignore[attr-defined]
from google.cloud import secretmanager

from constants import (
    API_MAX_TOKENS,
    API_TEMPERATURE,
    GEMINI_MODEL,
    GEMINI_MODEL_PREMIUM,
    RESPONSE_SCHEMA,
)
from nlp import enrich_with_nlp
from prompts import build_free_prompt, build_premium_prompt

initialize_app()

_IS_DEV = os.environ.get("GCLOUD_PROJECT", "") == "thai-memo-dev"


def _get_gemini_api_key() -> str:
    client = secretmanager.SecretManagerServiceClient()
    project_id = os.environ.get("GCLOUD_PROJECT", "")
    name = f"projects/{project_id}/secrets/gemini-api-key/versions/latest"
    response = client.access_secret_version(request={"name": name})
    api_key = response.payload.data.decode("UTF-8")
    if not api_key:
        raise RuntimeError("SECRET_MANAGER_ERROR")
    return api_key


def _generate_sentence(params: dict, is_premium: bool) -> dict:
    """Gemini APIで例文を生成し、NLP後処理を適用"""
    api_key = _get_gemini_api_key()
    client = genai.Client(api_key=api_key)

    model = GEMINI_MODEL_PREMIUM if is_premium else GEMINI_MODEL
    prompt = build_premium_prompt(params) if is_premium else build_free_prompt(params)
    tier_label = "premium" if is_premium else "free"

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


@https_fn.on_call(region="asia-northeast1", memory=2048, timeout_sec=120)
def generateThaiSentence(req: https_fn.CallableRequest) -> dict:
    start_time = time.time()
    response: dict = {"success": False}

    log_data = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "userId": req.auth.uid if req.auth else "anonymous",
        "requestedTopic": (req.data or {}).get("topic", "random"),
    }

    try:
        if not req.auth:
            log_data["error"] = "UNAUTHENTICATED"
            print(f"Authentication failed: {log_data}")
            response["error"] = {
                "code": "UNAUTHENTICATED",
                "message": "User must be authenticated",
            }
            return response

        print(f"Request started: {log_data}")

        # Quota check
        db: FirestoreClient = firestore.client()  # type: ignore[assignment]
        user_ref = db.collection("users").document(req.auth.uid)
        user_doc: DocumentSnapshot = user_ref.get()  # type: ignore[assignment]
        user_data = (user_doc.to_dict() or {}) if user_doc.exists else {}

        tier = user_data.get("tier", "free")
        is_premium = tier == "premium"

        remaining = user_data.get("remaining_sentences", 0)

        if remaining <= 0:
            response["error"] = {
                "code": "QUOTA_EXCEEDED",
                "message": "本日の例文生成上限に達しました",
            }
            return response

        sentence = _generate_sentence(req.data or {}, is_premium)

        processing_time = int((time.time() - start_time) * 1000)
        log_data["success"] = True
        log_data["processingTimeMs"] = processing_time

        response["success"] = True
        response["data"] = sentence

        # Save to Firestore + update quota
        try:
            db.collection("users").document(req.auth.uid).collection("sentences").add(
                {
                    "thai_text": sentence["thai_text"],
                    "pronunciation": sentence["pronunciation"],
                    "japanese_translation": sentence["japanese_translation"],
                    "created_at": firestore.firestore.SERVER_TIMESTAMP,
                }
            )
            user_ref.set(
                {"remaining_sentences": remaining - 1},
                merge=True,
            )
        except Exception as e:
            print(f"Failed to save sentence to Firestore: {e}")

        print(f"Request completed successfully: {log_data}")
        return response

    except Exception as e:
        processing_time = int((time.time() - start_time) * 1000)
        log_data["success"] = False
        log_data["processingTimeMs"] = processing_time
        error_msg = str(e)
        log_data["errorMessage"] = error_msg

        if "SECRET_MANAGER_ERROR" in error_msg:
            response["error"] = {
                "code": "INTERNAL",
                "message": "Failed to retrieve API configuration",
            }
        elif "GEMINI_API_ERROR" in error_msg:
            response["error"] = {
                "code": "API_ERROR",
                "message": "Failed to generate sentence",
            }
        else:
            response["error"] = {
                "code": "UNKNOWN",
                "message": "An unexpected error occurred",
            }

        print(f"Request failed: {log_data}")
        return response


def _current_slot_jst() -> str:
    """現在のJST時刻を30分スロット文字列（例: "14:30"）で返す"""
    now = datetime.now(ZoneInfo("Asia/Tokyo"))
    minute = 0 if now.minute < 30 else 30
    return f"{now.hour:02d}:{minute:02d}"


def _send_daily_sentence_handler(*, force: bool = False) -> None:
    """30分ごとに実行し、配信タイミングが合致するユーザーにFCM通知を送信する。

    1. 現在のJST時刻を30分スロットに変換（例: 14:15 → "14:00"）
    2. scheduled_time が合致するユーザーを取得（force=True時はスキップ）
    3. Gemini APIで例文を1つ生成（全対象ユーザー共通）
    4. 各ユーザーにFCM通知を送信

    Args:
        force: Trueの場合、スケジュール判定をスキップし全対象ユーザーに即時送信する
    """
    db: FirestoreClient = firestore.client()  # type: ignore[assignment]

    if force:
        print("sendDailySentence started: force=True (skip schedule filter)")
        users = (
            db.collection("users").where("notification_enabled", "==", True).stream()
        )
    else:
        current_slot = _current_slot_jst()
        print(f"sendDailySentence started: slot={current_slot}")
        users = (
            db.collection("users")
            .where("notification_enabled", "==", True)
            .where("scheduled_time", "==", current_slot)
            .stream()
        )

    # fcm_token を持つユーザーのみ抽出
    target_users = []
    for user_doc in users:
        user_data = user_doc.to_dict() or {}
        if user_data.get("fcm_token"):
            target_users.append((user_doc, user_data))

    if not target_users:
        print("No target users found")
        return

    # 対象ユーザーがいる場合のみ例文を生成（API呼び出し節約）
    sentence = _generate_sentence({}, is_premium=False)

    thai_text = sentence.get("thai_text", "")
    pronunciation = sentence.get("pronunciation", "")
    japanese_translation = sentence.get("japanese_translation", "")

    print(f"Generated sentence: {thai_text} / {pronunciation} / {japanese_translation}")

    # FCM data に完全な例文JSONを含める（通知タップ時にDetailScreen表示用）
    sentence_json = json.dumps(sentence, ensure_ascii=False)

    messages = []
    user_docs = []
    for user_doc, user_data in target_users:
        messages.append(
            messaging.Message(
                token=user_data["fcm_token"],
                notification=messaging.Notification(
                    title="今日のタイ語 🇹🇭",
                    body=f"{thai_text}\n{japanese_translation}",
                ),
                data={
                    "type": "daily_sentence",
                    "sentence_json": sentence_json,
                },
                apns=messaging.APNSConfig(
                    payload=messaging.APNSPayload(
                        aps=messaging.Aps(sound="default"),
                    ),
                ),
                android=messaging.AndroidConfig(
                    notification=messaging.AndroidNotification(
                        sound="default",
                        channel_id="daily_sentence",
                    ),
                ),
            )
        )
        user_docs.append(user_doc)

    sent_count = 0
    fail_count = 0

    if messages:
        response = messaging.send_each(messages)
        for i, send_response in enumerate(response.responses):
            if send_response.success:
                sent_count += 1
            elif isinstance(send_response.exception, messaging.UnregisteredError):
                db.collection("users").document(user_docs[i].id).update(
                    {
                        "fcm_token": firestore.firestore.DELETE_FIELD,
                    }
                )
                fail_count += 1
            else:
                print(
                    f"FCM send failed for {user_docs[i].id}: {send_response.exception}"
                )
                fail_count += 1

    print(f"sendDailySentence completed: sent={sent_count}, failed={fail_count}")


if _IS_DEV:

    @https_fn.on_request(region="asia-northeast1", memory=2048, timeout_sec=120)
    def sendDailySentenceHttp(req: https_fn.Request) -> https_fn.Response:  # type: ignore
        _send_daily_sentence_handler(force=True)
        return https_fn.Response("ok")  # type: ignore

    sendDailySentence = sendDailySentenceHttp
else:

    @scheduler_fn.on_schedule(
        schedule="*/30 8-20 * * *",
        region="asia-northeast1",
        timezone=scheduler_fn.Timezone("Asia/Tokyo"),  # type: ignore
        memory=2048,
        timeout_sec=120,
    )
    def sendDailySentenceScheduled(event: scheduler_fn.ScheduledEvent) -> None:
        _send_daily_sentence_handler()

    sendDailySentence = sendDailySentenceScheduled
