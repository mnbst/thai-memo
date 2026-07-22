"""毎日例文の配信バッチ。

毎時起動し、ユーザーのローカル時刻が配信希望時刻に一致する対象へ、
事前生成済みキャッシュから例文を1件作って Firestore に書き、FCMで通知する。
LLMは呼ばない（キャッシュミス時はターゲット語を引き直す）。
"""

from datetime import datetime, timezone

from firebase_admin import firestore, messaging
from firebase_functions import scheduler_fn  # type: ignore[attr-defined]
from google.cloud.firestore_v1 import transactional
from google.cloud.firestore_v1.base_query import FieldFilter
from google.cloud.firestore_v1.client import Client as FirestoreClient

try:
    from .constants import FREE_TIER_MAX_VOCAB
    from .daily_sentence import (
        MAX_TARGET_WORD_RETRY,
        TIER_STOPPED,
        evaluate_response,
        local_date,
        should_deliver,
    )
    from .prompts import use_premium_prompt_for_vocab
    from .runtime import initialize_firebase_app
    from .sentence_handlers import _build_sentence_data, _select_target_words_with_topic
    from .sentence_service import generate_sentence, pick_free_sentence
except ImportError:
    from constants import FREE_TIER_MAX_VOCAB
    from daily_sentence import (
        MAX_TARGET_WORD_RETRY,
        TIER_STOPPED,
        evaluate_response,
        local_date,
        should_deliver,
    )
    from prompts import use_premium_prompt_for_vocab
    from runtime import initialize_firebase_app
    from sentence_handlers import _build_sentence_data, _select_target_words_with_topic
    from sentence_service import generate_sentence, pick_free_sentence

initialize_firebase_app()

_EPOCH = datetime(1970, 1, 1, tzinfo=timezone.utc)


def _candidate_users(db: FirestoreClient):
    """生成実績のあるユーザーを列挙する（uid重複は除く）。

    Firestore は OR 条件で別フィールドの不等号を扱えないため2クエリに分ける。
    """
    seen: set[str] = set()
    queries = [
        db.collection("users").where(
            filter=FieldFilter("last_sentence_generated_at", ">", _EPOCH)
        ),
        db.collection("users").where(filter=FieldFilter("estimated_vocab", ">", 0)),
    ]
    for query in queries:
        for doc in query.stream():
            if doc.id in seen:
                continue
            seen.add(doc.id)
            yield doc.id, (doc.to_dict() or {})


def _pick_cached_sentence(
    db: FirestoreClient,
    uid: str,
    user_data: dict,
) -> tuple[dict, str] | None:
    """キャッシュから例文を1件選ぶ。ヒットしなければターゲット語を引き直す。"""
    estimated_vocab = min(user_data.get("estimated_vocab", 0), FREE_TIER_MAX_VOCAB)
    for _ in range(MAX_TARGET_WORD_RETRY):
        target_words, _topic = _select_target_words_with_topic(
            db,
            uid,
            {},
            is_premium=False,
            estimated_vocab=estimated_vocab,
        )
        cached = pick_free_sentence(target_words[0])
        if cached is not None:
            return cached, target_words[0]
    return None


def _generate_premium_sentence(
    db: FirestoreClient,
    uid: str,
    user_data: dict,
) -> tuple[dict, str] | None:
    """Premium ユーザー向けにLLMで例文を生成する。

    テーマはクライアントが users/{uid}.preferred_topic にミラーした設定を使う。
    未設定（おまかせ）なら通常生成と同じくUVMのkey_wordからテーマを決める。
    """
    estimated_vocab = user_data.get("estimated_vocab", 0)
    use_premium_prompt = use_premium_prompt_for_vocab(True, estimated_vocab)

    params: dict = {}
    preferred_topic = user_data.get("preferred_topic")
    if preferred_topic:
        params["topic"] = preferred_topic

    target_words, chosen_topic = _select_target_words_with_topic(
        db,
        uid,
        params,
        is_premium=use_premium_prompt,
        estimated_vocab=estimated_vocab,
    )
    params["topic"] = chosen_topic
    sentence = generate_sentence(
        params,
        True,
        target_words=target_words,
        estimated_vocab=estimated_vocab,
    )
    return sentence, target_words[0]


def _build_sentence(
    db: FirestoreClient,
    uid: str,
    user_data: dict,
) -> tuple[dict, str, bool] | None:
    """配信する例文を作る。戻り値は (例文, key_word, premiumスペックか)。

    free はトライアル残の有無によらずキャッシュのみ。LLM原価をゼロに保つのと、
    free 側の分岐を増やさないため。premium はLLMで生成し、失敗した場合だけ
    キャッシュに退避して通知そのものは落とさない。
    """
    if user_data.get("tier") == "premium":
        try:
            generated = _generate_premium_sentence(db, uid, user_data)
            if generated is not None:
                return generated[0], generated[1], True
        except Exception as exc:
            print(f"daily_sentence: premium generation failed for {uid}: {exc}")

    cached = _pick_cached_sentence(db, uid, user_data)
    if cached is None:
        return None
    return cached[0], cached[1], False


class _DeliveryNotDue(Exception):
    """トランザクション内の再判定で配信条件を満たさなくなった。"""


class _DeliveryStopped(Exception):
    """段階が配信停止に達した。updates は呼び出し側が書く。

    トランザクション内で update しても、例外を投げた時点で rollback され
    書き込みごと捨てられるため、停止の記録はトランザクション外で行う。
    """

    def __init__(self, updates: dict) -> None:
        super().__init__("DELIVERY_STOPPED")
        self.updates = updates


def _commit_daily_sentence_body(
    transaction,
    user_ref,
    sentence_ref,
    sentence_data: dict,
    now: datetime,
) -> tuple[str, dict]:
    """例文docの書き込みとクォータ消費・段階更新を1トランザクションで行う。

    戻り値は (送信先トークン, 通知失敗時に段階を戻すための更新内容)。

    last_sentence_generated_at は書かない。あれは「次へ」押下＝反応のシグナルであり、
    配信そのものを反応として数えてはいけない。
    """
    user_snapshot = user_ref.get(transaction=transaction)
    user_data = (user_snapshot.to_dict() or {}) if user_snapshot.exists else {}

    # 外側の列挙結果は古い可能性があるため、二重配信を防ぐ正の判定は
    # トランザクション内の最新 user doc で行う。
    if not should_deliver(user_data, now):
        raise _DeliveryNotDue

    tier_update = evaluate_response(user_data)
    if tier_update["notify_tier"] >= TIER_STOPPED:
        raise _DeliveryStopped(
            {"last_notified_at": firestore.firestore.SERVER_TIMESTAMP, **tier_update}
        )

    restore = {
        "notify_tier": user_data.get("notify_tier", 0),
        "notify_tier_misses": user_data.get("notify_tier_misses", 0),
        "last_notified_at": user_data.get("last_notified_at")
        or firestore.firestore.DELETE_FIELD,
    }

    transaction.set(sentence_ref, sentence_data)
    transaction.update(
        user_ref,
        {
            "remaining_sentences": firestore.firestore.Increment(-1),
            "daily_sentence_generated": True,
            "last_notified_at": firestore.firestore.SERVER_TIMESTAMP,
            **tier_update,
        },
    )
    return user_data["fcm_token"], restore


_commit_daily_sentence = transactional(_commit_daily_sentence_body)


def _send_notification(token: str, sentence: dict) -> None:
    messaging.send(
        messaging.Message(
            token=token,
            notification=messaging.Notification(
                title=sentence["thai_text"],
                body=sentence["japanese_translation"],
            ),
            data={"type": "daily_sentence"},
        )
    )


def _rollback_delivery(user_ref, sentence_ref, restore: dict) -> None:
    """通知が届かなかった場合に配信をなかったことにする。

    段階（notify_tier）も配信前に戻す。届いていない通知を無反応として数えると、
    ユーザーが身に覚えのないまま配信停止へ近づいてしまうため。
    """
    sentence_ref.delete()
    user_ref.update(
        {
            "remaining_sentences": firestore.firestore.Increment(1),
            "daily_sentence_generated": False,
            "fcm_token": firestore.firestore.DELETE_FIELD,
            **restore,
        }
    )


def _deliver_one(
    db: FirestoreClient,
    uid: str,
    user_data: dict,
    now: datetime,
) -> bool:
    user_ref = db.collection("users").document(uid)

    if user_data.get("tier") == "premium":
        # LLM を叩く前に最新状態を読み直す。二重配信自体はトランザクションで
        # 弾けるが、生成コストは commit 前に払ってしまうため窓を狭めておく。
        snapshot = user_ref.get()
        user_data = (snapshot.to_dict() or {}) if snapshot.exists else {}
        if not should_deliver(user_data, now):
            return False

    picked = _build_sentence(db, uid, user_data)
    if picked is None:
        print(f"daily_sentence: no sentence available for {uid}")
        return False
    sentence, key_word, use_premium_spec = picked

    sentence_data = {
        **_build_sentence_data(sentence, key_word, use_premium_spec=use_premium_spec),
        "daily": True,
        "daily_date": local_date(user_data.get("timezone"), now),
    }
    sentence_ref = user_ref.collection("sentences").document()

    try:
        token, restore = _commit_daily_sentence(
            db.transaction(),
            user_ref,
            sentence_ref,
            sentence_data,
            now,
        )
    except _DeliveryNotDue:
        return False
    except _DeliveryStopped as stopped:
        user_ref.update(stopped.updates)
        return False

    try:
        _send_notification(token, sentence)
    except messaging.UnregisteredError:
        print(f"daily_sentence: token unregistered, rolling back {uid}")
        _rollback_delivery(user_ref, sentence_ref, restore)
        return False
    return True


@scheduler_fn.on_schedule(
    schedule="0 * * * *",
    region="asia-northeast1",
    memory=2048,
    timeout_sec=540,
)
def deliverDailySentence(event: scheduler_fn.ScheduledEvent) -> None:
    db = firestore.client()
    now = datetime.now(timezone.utc)
    delivered = 0
    skipped = 0

    for uid, user_data in _candidate_users(db):
        if not should_deliver(user_data, now):
            continue
        try:
            if _deliver_one(db, uid, user_data, now):
                delivered += 1
            else:
                skipped += 1
        except Exception as exc:
            skipped += 1
            print(f"daily_sentence: delivery failed for {uid}: {exc}")

    print(f"daily_sentence: delivered={delivered} skipped={skipped}")
