from firebase_admin import firestore
from firebase_functions import https_fn  # type: ignore[attr-defined]
from google.cloud.firestore_v1.client import Client as FirestoreClient

try:
    from .runtime import initialize_firebase_app
    from .sentence_service import get_freq_rank
    from .uvm import batch_update_uvm
except ImportError:
    from runtime import initialize_firebase_app
    from sentence_service import get_freq_rank
    from uvm import batch_update_uvm

initialize_firebase_app()


@https_fn.on_call(region="asia-northeast1", memory=2048, timeout_sec=30, concurrency=20)
def updateUvm(req: https_fn.CallableRequest) -> dict:
    """クイズ結果からUVMを更新する。"""
    if not req.auth:
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.UNAUTHENTICATED,
            message="認証が必要です",
        )

    uid = req.auth.uid
    db: FirestoreClient = firestore.client()  # type: ignore[assignment]

    data = req.data or {}
    results: list[dict] = data.get("results", [])
    if not results:
        return {"success": True, "updated": 0}

    quiz_type: str = data.get("quiz_type", "")
    freq_rank = get_freq_rank()

    user_doc = db.collection("users").document(uid).get()
    user_data = user_doc.to_dict() or {} if user_doc.exists else {}
    is_premium = user_data.get("tier") == "premium"

    print(f"updateUvm: uid={uid}, quiz_type={quiz_type}, results={results}")
    batch_update_uvm(db, uid, results, freq_rank=freq_rank, quiz_type=quiz_type, is_premium=is_premium)  # type: ignore

    try:
        correct_count = sum(1 for r in results if r.get("is_correct") is True)
        db.collection("users").document(uid).set(
            {
                "last_active_at": firestore.firestore.SERVER_TIMESTAMP,
                "last_quiz_answered_at": firestore.firestore.SERVER_TIMESTAMP,
                "quiz_answer_count": firestore.firestore.Increment(len(results)),
                "quiz_correct_count": firestore.firestore.Increment(correct_count),
            },
            merge=True,
        )
    except Exception as exc:
        print(f"updateUvm metrics update failed: uid={uid}, error={exc}")

    print(f"updateUvm completed: uid={uid}, updated={len(results)}")

    return {"success": True, "updated": len(results)}
