import os

from firebase_admin import get_app, initialize_app
from firebase_functions import https_fn  # type: ignore[attr-defined]


def initialize_firebase_app() -> None:
    try:
        get_app()
    except ValueError:
        initialize_app()


initialize_firebase_app()

IS_DEV = os.environ.get("GCLOUD_PROJECT", "") == "thai-memo-dev"


def verify_app_check(req: https_fn.CallableRequest) -> None:
    """dev環境以外で App Check token を検証する。"""
    if IS_DEV:
        return
    if req.app is None:
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.UNAUTHENTICATED,
            message="App Checkの検証に失敗しました",
        )
