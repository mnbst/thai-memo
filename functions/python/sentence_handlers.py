import time
from datetime import datetime, timezone

from firebase_admin import firestore
from firebase_functions import https_fn  # type: ignore[attr-defined]

try:
    from .runtime import initialize_firebase_app
    from .sentence_service import (
        generate_sentence,
        select_uvm_target_words,
    )
    from .uvm import get_exposed_words, get_sentence_words, register_exposure
except ImportError:
    from runtime import initialize_firebase_app
    from sentence_service import generate_sentence, select_uvm_target_words
    from uvm import get_exposed_words, get_sentence_words, register_exposure

initialize_firebase_app()


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

        db = firestore.client()
        user_ref = db.collection("users").document(req.auth.uid)  # type: ignore[union-attr]
        user_doc = user_ref.get()  # type: ignore[union-attr]
        user_data = (user_doc.to_dict() or {}) if user_doc.exists else {}  # type: ignore[union-attr]

        tier = user_data.get("tier", "free")
        is_premium = tier == "premium"

        remaining = user_data.get("remaining_sentences", 0)
        if remaining <= 0:
            response["error"] = {
                "code": "QUOTA_EXCEEDED",
                "message": "本日の例文生成上限に達しました",
            }
            return response

        params = req.data or {}
        target_words: list[str] | None = None
        if is_premium:
            try:
                target_words = select_uvm_target_words(db, req.auth.uid, params)  # type: ignore[union-attr]
                log_data["uvmWords"] = len(target_words)
            except Exception as exc:
                print(f"UVM word selection failed, falling back to standard: {exc}")

        estimated_vocab = user_data.get("estimated_vocab", 0)
        sentence = generate_sentence(
            params, is_premium, target_words=target_words, estimated_vocab=estimated_vocab
        )

        processing_time = int((time.time() - start_time) * 1000)
        log_data["success"] = True
        log_data["processingTimeMs"] = processing_time

        response["success"] = True
        response["data"] = sentence

        if target_words:
            exposed_words = get_exposed_words(sentence, target_words)
            log_data["uvmMatchedWords"] = len(exposed_words)
            if exposed_words:
                register_exposure(
                    db,
                    req.auth.uid,  # type: ignore[union-attr]
                    exposed_words,
                    create_new=True,
                )
            # key_word 以外の既存UVM単語も露出更新
            all_words = get_sentence_words(sentence)
            other_words = [w for w in all_words if w not in set(target_words)]
            if other_words:
                register_exposure(
                    db,
                    req.auth.uid,  # type: ignore[union-attr]
                    other_words,
                )

        try:
            sentence_data = {
                    "thai_text": sentence["thai_text"],
                    "pronunciation": sentence["pronunciation"],
                    "japanese_translation": sentence["japanese_translation"],
                    "created_at": firestore.firestore.SERVER_TIMESTAMP,
                }
            if target_words:
                sentence_data["key_word"] = target_words[0]
            db.collection("users").document(req.auth.uid).collection("sentences").add(sentence_data)
            user_ref.set(
                {"remaining_sentences": remaining - 1},
                merge=True,
            )
        except Exception as exc:
            print(f"Failed to save sentence to Firestore: {exc}")

        print(f"Request completed successfully: {log_data}")
        return response

    except Exception as exc:
        processing_time = int((time.time() - start_time) * 1000)
        log_data["success"] = False
        log_data["processingTimeMs"] = processing_time
        error_msg = str(exc)
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
