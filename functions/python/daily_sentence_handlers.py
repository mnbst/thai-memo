"""毎日例文の配信バッチ。

毎時起動し、ユーザーのローカル時刻が配信希望時刻に一致する対象へ、
通常生成と共通の生成コア（produce_sentence）で例文を1件作って Firestore に書き、
FCMで通知する。free はキャッシュのみでLLMは呼ばない（ミス時はターゲット語を
引き直す）。premium と、プレミアム体験トライアル枠を充てる配信はLLM生成し、
失敗時はキャッシュに退避する。
通知の送信成功後に露出登録（UVM）を行い、通常生成と語彙状態を揃える。
"""

import traceback
from collections import Counter
from datetime import datetime, timezone

from firebase_admin import firestore, messaging
from firebase_functions import scheduler_fn  # type: ignore[attr-defined]
from google.cloud.firestore_v1 import transactional
from google.cloud.firestore_v1.base_query import FieldFilter
from google.cloud.firestore_v1.client import Client as FirestoreClient

try:
    from .constants import FREE_TIER_MAX_VOCAB, normalize_lang
    from .daily_sentence import (
        MAX_TARGET_WORD_RETRY,
        TIER_STOPPED,
        delivery_skip_reason,
        evaluate_response,
        local_date,
        should_deliver,
        uses_premium_trial,
    )
    from .runtime import initialize_firebase_app
    from .sentence_handlers import (
        _build_sentence_data,
        _register_sentence_exposure,
        produce_sentence,
    )
    from .sentence_service import get_freq_rank, resolve_interview_topic
    from .uvm import sync_estimated_vocab
except ImportError:
    from constants import FREE_TIER_MAX_VOCAB, normalize_lang
    from daily_sentence import (
        MAX_TARGET_WORD_RETRY,
        TIER_STOPPED,
        delivery_skip_reason,
        evaluate_response,
        local_date,
        should_deliver,
        uses_premium_trial,
    )
    from runtime import initialize_firebase_app
    from sentence_handlers import (
        _build_sentence_data,
        _register_sentence_exposure,
        produce_sentence,
    )
    from sentence_service import get_freq_rank, resolve_interview_topic
    from uvm import sync_estimated_vocab

initialize_firebase_app()


def _candidate_users(db: FirestoreClient, now: datetime):
    """この時刻に配信されうるユーザーだけを列挙する。

    users 全件を毎時読むと読み取りが 24×N/日 になるため、非正規化した
    notify_utc_hour（現地の配信希望時刻に対応するUTC時刻）で絞り込む。
    これで 1日あたり各ユーザー1回しか読まない。

    この値はあくまで足切り用で、配信の可否は従来どおり should_deliver 内の
    ローカル時刻比較が最終判定を行う（値が古くても誤配信にはならない）。
    フィールドは dailyBatch が毎日全ユーザーに書き直すため、旧クライアントでも
    1日以内に埋まる。
    """
    query = db.collection("users").where(
        filter=FieldFilter("notify_utc_hour", "==", now.astimezone(timezone.utc).hour)
    )
    for doc in query.stream():
        yield doc.id, (doc.to_dict() or {})


def _build_sentence(
    db: FirestoreClient,
    uid: str,
    user_data: dict,
) -> tuple[dict, list[str], bool] | None:
    """配信する例文を作る。戻り値は (例文, target_words, premiumスペックか)。

    生成コアは通常生成と共通の produce_sentence。
    訳文の言語はサーバー起点でリクエストが無いため、クライアントが
    users/{uid}.app_language にミラーした設定から解決する。渡し忘れると
    produce_sentence の既定値 ja に落ち、en ユーザーの配信だけ日本語になる
    （2026-08-14 実測: en ユーザーの配信例文10本が全て日本語訳だった）。
    free はキャッシュのみでLLM原価をゼロに保つ。premium と、トライアル枠を充てる
    配信（uses_premium_trial）はLLMで生成し、失敗した場合だけキャッシュに退避して
    通知そのものは落とさない。
    premium のテーマはクライアントが users/{uid}.preferred_topic にミラーした
    設定を使い、未設定（おまかせ）ならヒアリングの用途（interview.goal）から
    決める。どちらも無ければ通常生成と同じくUVMのkey_wordから決める。
    """
    lang = normalize_lang(user_data.get("app_language"))

    if user_data.get("tier") == "premium" or uses_premium_trial(user_data):
        params: dict = {}
        # 本人が選んだテーマ > ヒアリングの用途 > key_word 起点の自動選出。
        preferred_topic = user_data.get("preferred_topic") or resolve_interview_topic(
            user_data
        )
        if preferred_topic:
            params["topic"] = preferred_topic
        try:
            produced = produce_sentence(
                db,
                uid,
                params,
                use_premium_spec=True,
                estimated_vocab=user_data.get("estimated_vocab", 0),
                lang=lang,
            )
            if produced is not None:
                sentence, target_words, _topic, _cached = produced
                return sentence, target_words, True
        except Exception as exc:
            print(f"daily_sentence: premium generation failed for {uid}: {exc}")

    produced = produce_sentence(
        db,
        uid,
        {},
        use_premium_spec=False,
        estimated_vocab=min(
            user_data.get("estimated_vocab", 0), FREE_TIER_MAX_VOCAB
        ),
        cache_only=True,
        select_retry=MAX_TARGET_WORD_RETRY,
        lang=lang,
    )
    if produced is None:
        return None
    sentence, target_words, _topic, _cached = produced
    return sentence, target_words, False


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


# 通知タイトルの言語別テンプレート。本文は例文そのもの（タイ文・発音・訳）なので
# 訳文の言語で決まるが、タイトルはサーバー側の文言なのでここで出し分ける。
_NOTIFICATION_TITLE = {
    "ja": ("🇹🇭 今日のタイ語", "🇹🇭 今日のタイ語 · {key_word}（{meaning}）"),
    "en": ("🇹🇭 Thai of the Day", "🇹🇭 Thai of the Day · {key_word} ({meaning})"),
}


def build_notification_text(sentence: dict, lang: str = "ja") -> tuple[str, str]:
    """通知のタイトルと本文を組み立てる。

    タイ文字だけだと通知一覧で何のアプリか判別しづらいので、タイトルに
    キーワードとその意味を載せて「今日の学習が届いた」と一目で分かるようにする。
    本文は タイ文 / 発音 / 訳 の3行。3行は並列な項目ではなく1つの例文の3側面なので、
    同じ記号を並べず、発音は括弧・訳は矢印で役割を書き分ける。
    発音が無い例文もあるので行ごとに省く。
    """
    plain, with_word = _NOTIFICATION_TITLE.get(lang, _NOTIFICATION_TITLE["ja"])
    key_word = (sentence.get("key_word") or "").strip()
    key_word_meaning = (sentence.get("key_word_meaning") or "").strip()
    if key_word and key_word_meaning:
        title = with_word.format(key_word=key_word, meaning=key_word_meaning)
    elif key_word:
        title = f"{plain} · {key_word}"
    else:
        title = plain

    thai_text = (sentence.get("thai_text") or "").strip()
    pronunciation = (sentence.get("pronunciation") or "").strip()
    translation = (sentence.get("japanese_translation") or "").strip()

    lines = [
        thai_text,
        f"（{pronunciation}）" if pronunciation else "",
        f"→ {translation}" if translation else "",
    ]
    return title, "\n".join(line for line in lines if line)


def _send_notification(
    token: str, sentence_id: str, sentence: dict, lang: str = "ja"
) -> None:
    title, body = build_notification_text(sentence, lang)
    messaging.send(
        messaging.Message(
            token=token,
            notification=messaging.Notification(title=title, body=body),
            # 複数行の本文は展開しないと切られるため、Android は BigText 相当の
            # 表示になるよう優先度を上げ、iOS はロック画面で読み上げ枠を確保する。
            android=messaging.AndroidConfig(
                priority="high",
                notification=messaging.AndroidNotification(
                    body=body,
                    default_sound=True,
                ),
            ),
            apns=messaging.APNSConfig(
                payload=messaging.APNSPayload(
                    aps=messaging.Aps(sound="default"),
                ),
            ),
            data={"type": "daily_sentence", "sentence_id": sentence_id},
        )
    )


def _rollback_delivery(
    user_ref, sentence_ref, restore: dict, *, delete_token: bool = True
) -> None:
    """通知が届かなかった場合に配信をなかったことにする。

    段階（notify_tier）も配信前に戻す。届いていない通知を無反応として数えると、
    ユーザーが身に覚えのないまま配信停止へ近づいてしまうため。

    delete_token はトークン失効（UnregisteredError）のときだけ True にする。
    権限不足やFCM障害でトークンまで消すと、原因を直しても配信対象から永久に
    外れてしまう（再登録はアプリ再起動待ちになる）。
    """
    sentence_ref.delete()
    user_ref.update(
        {
            "remaining_sentences": firestore.firestore.Increment(1),
            "daily_sentence_generated": False,
            **(
                {"fcm_token": firestore.firestore.DELETE_FIELD}
                if delete_token
                else {}
            ),
            **restore,
        }
    )


def _deliver_one(
    db: FirestoreClient,
    uid: str,
    user_data: dict,
    now: datetime,
) -> str | None:
    """1件配信する。配信できたら None、できなければ理由を返す（ログ集計用）。"""
    user_ref = db.collection("users").document(uid)

    if user_data.get("tier") == "premium" or uses_premium_trial(user_data):
        # LLM を叩く前に最新状態を読み直す。二重配信自体はトランザクションで
        # 弾けるが、生成コストは commit 前に払ってしまうため窓を狭めておく。
        snapshot = user_ref.get()
        user_data = (snapshot.to_dict() or {}) if snapshot.exists else {}
        reason = delivery_skip_reason(user_data, now)
        if reason:
            return f"stale:{reason}"

    picked = _build_sentence(db, uid, user_data)
    if picked is None:
        print(f"daily_sentence: no sentence available for {uid}")
        return "no_sentence"
    sentence, target_words, use_premium_spec = picked

    sentence_data = {
        **_build_sentence_data(
            sentence, target_words[0], use_premium_spec=use_premium_spec
        ),
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
        return "not_due_at_commit"
    except _DeliveryStopped as stopped:
        user_ref.update(stopped.updates)
        return "backoff_stopped_now"

    try:
        # key_word とその意味を通知に載せるため、整形済みの sentence_data を渡す。
        _send_notification(
            token,
            sentence_ref.id,
            sentence_data,
            normalize_lang(user_data.get("app_language")),
        )
    except messaging.UnregisteredError:
        print(f"daily_sentence: token unregistered, rolling back {uid}")
        _rollback_delivery(user_ref, sentence_ref, restore)
        return "token_unregistered"
    except Exception as exc:
        # トークン失効以外の送信失敗（権限・FCM障害など）。以前はここを素通りして
        # 上位で握っていたため、通知が飛ばないのにクォータと当日フラグだけ消費されていた。
        print(f"daily_sentence: send failed for {uid}: {exc!r}")
        traceback.print_exc()
        _rollback_delivery(user_ref, sentence_ref, restore, delete_token=False)
        return "send_failed"

    # 露出登録は通知が届いた後にだけ行う。配信をロールバックしても
    # UVM の P 微増は巻き戻せないため、送信成功を確認してから登録する。
    try:
        _register_sentence_exposure(db, uid, sentence, target_words)
        sync_estimated_vocab(
            db,
            uid,
            get_freq_rank(),
            max_vocab=(
                None
                if user_data.get("tier") == "premium"
                else FREE_TIER_MAX_VOCAB
            ),
        )
    except Exception as exc:
        print(f"daily_sentence: uvm update failed for {uid}: {exc}")
    return None


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
    reasons: Counter[str] = Counter()

    for uid, user_data in _candidate_users(db, now):
        reason = delivery_skip_reason(user_data, now)
        if reason is None:
            try:
                reason = _deliver_one(db, uid, user_data, now)
            except Exception as exc:
                reason = "error"
                print(f"daily_sentence: delivery failed for {uid}: {exc!r}")
                traceback.print_exc()
        if reason is None:
            delivered += 1
        else:
            reasons[reason] += 1

    # 内訳は「なぜ通知が届いていないのか」を後から追うための常設ログ。
    # 候補は notify_utc_hour で絞った後なので、母数はこの時刻の配信希望者だけ。
    breakdown = " ".join(f"{k}={v}" for k, v in sorted(reasons.items()))
    print(
        f"daily_sentence: delivered={delivered} skipped={sum(reasons.values())}"
        + (f" [{breakdown}]" if breakdown else "")
    )
