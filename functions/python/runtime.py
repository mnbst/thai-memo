import os

from firebase_admin import get_app, initialize_app


def initialize_firebase_app() -> None:
    try:
        get_app()
    except ValueError:
        initialize_app()


initialize_firebase_app()

IS_DEV = os.environ.get("GCLOUD_PROJECT", "") == "thai-memo-dev"
