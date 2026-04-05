import os

from firebase_admin import get_app, initialize_app
from firebase_functions import https_fn  # type: ignore[attr-defined]


def initialize_firebase_app() -> None:
    try:
        get_app()
    except ValueError:
        initialize_app()


initialize_firebase_app()

