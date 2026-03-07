import json
import os
import time
from datetime import datetime, timezone
from zoneinfo import ZoneInfo

from google import genai
from firebase_admin import firestore, initialize_app, messaging
from firebase_admin.exceptions import FirebaseError
from google.cloud.firestore_v1.base_document import DocumentSnapshot
from google.cloud.firestore_v1.client import Client as FirestoreClient
from firebase_functions import https_fn, scheduler_fn
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

        today = datetime.now(ZoneInfo("Asia/Tokyo")).strftime("%Y-%m-%d")
        last_date = user_data.get("last_generation_date", "")
        daily_count = user_data.get("daily_generation_count", 0)
        if last_date != today:
            daily_count = 0

        max_count = 5 if is_premium else 1
        if daily_count >= max_count:
            response["error"] = {
                "code": "QUOTA_EXCEEDED",
                "message": "本日の例文生成上限（5回）に達しました",
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
                {
                    "daily_generation_count": daily_count + 1,
                    "last_generation_date": today,
                },
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


def _send_daily_sentence_handler() -> None:
    """1日1回、全ユーザーにタイ語例文をFCM通知で配信する。

    1. Gemini APIで短文のタイ語例文を1つ生成（全ユーザー共通）
    2. notification_enabled=true かつ fcm_token を持つユーザーを取得
    3. 各ユーザーにFCM通知を送信（例文データをペイロードに含む）
    """
    print("sendDailySentence started")

    # 全ユーザー共通の例文を1つ生成（無料ティアのロジックを使用）
    sentence = _generate_sentence({}, is_premium=False)

    thai_text = sentence.get("thai_text", "")
    pronunciation = sentence.get("pronunciation", "")
    japanese_translation = sentence.get("japanese_translation", "")

    print(f"Generated sentence: {thai_text} / {pronunciation} / {japanese_translation}")

    # notification_enabled=true のユーザーを取得
    db: FirestoreClient = firestore.client()  # type: ignore[assignment]
    users = db.collection("users").where("notification_enabled", "==", True).stream()

    sent_count = 0
    fail_count = 0

    for user_doc in users:
        user_data = user_doc.to_dict() or {}
        fcm_token = user_data.get("fcm_token")
        if not fcm_token:
            continue

        try:
            msg = messaging.Message(
                token=fcm_token,
                notification=messaging.Notification(
                    title="今日のタイ語 🇹🇭",
                    body=f"{thai_text}\n{pronunciation}\n{japanese_translation}",
                ),
                data={
                    "type": "daily_sentence",
                    "thai_text": thai_text,
                    "pronunciation": pronunciation,
                    "japanese_translation": japanese_translation,
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
            messaging.send(msg)
            sent_count += 1
        except messaging.UnregisteredError:
            # トークン無効（アプリ削除等）→ fcm_token を削除
            db.collection("users").document(user_doc.id).update({
                "fcm_token": firestore.firestore.DELETE_FIELD,
            })
            fail_count += 1
        except FirebaseError as e:
            print(f"FCM send failed for {user_doc.id}: {e}")
            fail_count += 1

    print(f"sendDailySentence completed: sent={sent_count}, failed={fail_count}")


if _IS_DEV:
    @https_fn.on_request(region="asia-northeast1", memory=2048, timeout_sec=120)
    def sendDailySentence(req: https_fn.Request) -> https_fn.Response:
        _send_daily_sentence_handler()
        return https_fn.Response("ok")
else:
    @scheduler_fn.on_schedule(
        schedule="0 8 * * *",
        region="asia-northeast1",
        timezone=scheduler_fn.Timezone("Asia/Tokyo"),
        memory=2048,
        timeout_sec=120,
    )
    def sendDailySentence(event: scheduler_fn.ScheduledEvent) -> None:
        _send_daily_sentence_handler()
