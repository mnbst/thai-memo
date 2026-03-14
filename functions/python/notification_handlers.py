import json
from datetime import datetime
from zoneinfo import ZoneInfo

from firebase_admin import firestore, messaging
from firebase_functions import https_fn, scheduler_fn  # type: ignore[attr-defined]
from google.cloud.firestore_v1.client import Client as FirestoreClient

try:
    from .runtime import IS_DEV, initialize_firebase_app
    from .sentence_service import generate_sentence
except ImportError:
    from runtime import IS_DEV, initialize_firebase_app
    from sentence_service import generate_sentence

initialize_firebase_app()


def _current_slot_jst() -> str:
    """現在のJST時刻を30分スロット文字列で返す。"""
    now = datetime.now(ZoneInfo("Asia/Tokyo"))
    minute = 0 if now.minute < 30 else 30
    return f"{now.hour:02d}:{minute:02d}"


def _send_daily_sentence_handler(*, force: bool = False) -> None:
    """配信対象ユーザーにFCMで日次例文を送信する。"""
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

    target_users = []
    for user_doc in users:
        user_data = user_doc.to_dict() or {}
        if user_data.get("fcm_token"):
            target_users.append((user_doc, user_data))

    if not target_users:
        print("No target users found")
        return

    sentence = generate_sentence({}, is_premium=False)

    thai_text = sentence.get("thai_text", "")
    japanese_translation = sentence.get("japanese_translation", "")

    print(
        "Generated sentence: "
        f"{thai_text} / {sentence.get('pronunciation', '')} / {japanese_translation}"
    )

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
            print(f"FCM send failed for {user_docs[i].id}: {send_response.exception}")
            fail_count += 1

    print(f"sendDailySentence completed: sent={sent_count}, failed={fail_count}")


if IS_DEV:

    @https_fn.on_request(region="asia-northeast1", memory=2048, timeout_sec=120)
    def sendDailySentence(_req: https_fn.Request) -> https_fn.Response:  # type: ignore
        _send_daily_sentence_handler(force=True)
        return https_fn.Response("ok")  # type: ignore

else:

    @scheduler_fn.on_schedule(
        schedule="*/30 8-20 * * *",
        region="asia-northeast1",
        timezone=scheduler_fn.Timezone("Asia/Tokyo"),  # type: ignore
        memory=2048,
        timeout_sec=120,
    )
    def sendDailySentence(_event: scheduler_fn.ScheduledEvent) -> None:
        _send_daily_sentence_handler()
