from firebase_admin import firestore
from firebase_functions import https_fn  # type: ignore[attr-defined]
from google.cloud.firestore_v1.client import Client as FirestoreClient

try:
    from .runtime import initialize_firebase_app, verify_app_check
    from .sentence_service import get_freq_rank
    from .uvm import batch_update_uvm
except ImportError:
    from runtime import initialize_firebase_app, verify_app_check
    from sentence_service import get_freq_rank
    from uvm import batch_update_uvm

initialize_firebase_app()


@https_fn.on_call(region="asia-northeast1", memory=2048, timeout_sec=30)
def updateUvm(req: https_fn.CallableRequest) -> dict:
    """クイズ結果からUVMを更新する。"""
    verify_app_check(req)

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

    freq_rank = get_freq_rank()
    batch_update_uvm(db, uid, results, freq_rank=freq_rank)  # type: ignore

    print(f"updateUvm completed: uid={uid}, updated={len(results)}")

    return {"success": True, "updated": len(results)}
