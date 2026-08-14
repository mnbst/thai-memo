import os
import threading
import time
from datetime import datetime, timedelta, timezone

from firebase_admin import firestore
from firebase_functions import https_fn  # type: ignore[attr-defined]
from google.cloud.firestore_v1.client import Client as FirestoreClient
from google.cloud.firestore_v1 import transactional

try:
    from .constants import (
        FREE_TIER_MAX_VOCAB,
        PREMIUM_DAILY_QUIZZES,
        PREMIUM_DAILY_SENTENCES,
        PREMIUM_TRIAL_DAYS,
        PREMIUM_TRIAL_SENTENCES,
        resolve_lang,
    )
    from .prompts import use_premium_prompt_for_vocab
    from .runtime import initialize_firebase_app
    from .sentence_service import (
        generate_sentence,
        get_freq_rank,
        pick_free_sentence,
        require_target_words,
        select_uvm_target_words,
    )
    from .uvm import (
        get_exposed_words,
        get_sentence_words,
        register_exposure,
        sync_estimated_vocab,
    )
except ImportError:
    from constants import (
        FREE_TIER_MAX_VOCAB,
        PREMIUM_DAILY_QUIZZES,
        PREMIUM_DAILY_SENTENCES,
        PREMIUM_TRIAL_DAYS,
        PREMIUM_TRIAL_SENTENCES,
        resolve_lang,
    )
    from prompts import use_premium_prompt_for_vocab
    from runtime import initialize_firebase_app
    from sentence_service import (
        generate_sentence,
        get_freq_rank,
        pick_free_sentence,
        require_target_words,
        select_uvm_target_words,
    )
    from uvm import (
        get_exposed_words,
        get_sentence_words,
        register_exposure,
        sync_estimated_vocab,
    )

initialize_firebase_app()


def _get_capped_estimated_vocab(user_data: dict, is_premium: bool) -> int:
    estimated_vocab = user_data.get("estimated_vocab", 0)
    if not is_premium:
        estimated_vocab = min(estimated_vocab, FREE_TIER_MAX_VOCAB)
    return estimated_vocab


def _select_target_words_with_topic(
    db: FirestoreClient,
    uid: str,
    params: dict,
    *,
    is_premium: bool,
    estimated_vocab: int,
    count: int = 1,
) -> tuple[list[str], str]:
    max_vocab = None if is_premium else FREE_TIER_MAX_VOCAB
    return require_target_words(
        select_uvm_target_words(
            db,
            uid,
            params,
            max_vocab=max_vocab,
            count=count,
            is_premium=is_premium,
            estimated_vocab=estimated_vocab,
        )
    )


_JST = timezone(timedelta(hours=9))


def _ceil_to_jst_midnight(value: datetime) -> datetime:
    """value 以降で最初の JST 0:00 を返す（ちょうど 0:00 ならそのまま）。"""
    local = value.astimezone(_JST)
    midnight = local.replace(hour=0, minute=0, second=0, microsecond=0)
    if midnight < local:
        midnight += timedelta(days=1)
    return midnight.astimezone(timezone.utc)


def _trial_expires_at(user_data: dict) -> datetime | None:
    """トライアル期限を tz-aware な datetime で返す。旧docには無いので None。"""
    value = user_data.get("premium_trial_expires_at")
    if not isinstance(value, datetime):
        return None
    if value.tzinfo is None:
        return value.replace(tzinfo=timezone.utc)
    return value


def _resolve_trial_active(
    *,
    is_premium: bool,
    trial_expires_at: datetime | None,
    now: datetime,
) -> bool:
    """この生成を premium ロジックに切り替えるか判定する。

    トライアルは期間制で、期間中は完全に premium と同じ扱いにする。
    クライアントの申告（premium_trial）は見ない。旧クライアントでも同じ体験に
    なるべきで、申告に依存させると端末ごとに差が出る。
    premium ユーザーは tier 側で premium 扱いになるので False。
    """
    if is_premium or trial_expires_at is None:
        return False
    return now < trial_expires_at


def _effective_generation_params(params: dict, *, is_premium: bool) -> dict:
    """Free users always use automatic topic selection."""
    effective = dict(params)
    effective.pop("premium_trial", None)
    # lang は生成条件ではなく出力言語の指定。ここに残すとプロンプトの
    # 「条件」ブロックに未知のキーとして流れ込むので取り除く。
    effective.pop("lang", None)
    if not is_premium:
        effective.pop("topic", None)
    return effective


def _register_sentence_exposure(
    db: FirestoreClient,
    uid: str,
    sentence: dict,
    target_words: list[str],
) -> int:
    all_words = get_sentence_words(sentence)
    exposed_words = get_exposed_words(sentence, target_words)
    if exposed_words:
        register_exposure(db, uid, exposed_words, target_words=target_words)

    other_words = [w for w in all_words if w not in set(target_words)]
    if other_words:
        register_exposure(db, uid, other_words)

    return len(exposed_words)


def _generation_tier(use_premium_spec: bool) -> str:
    return "premium" if use_premium_spec else "free"


def _attach_generation_tier(sentence: dict, use_premium_spec: bool) -> dict:
    return {
        **sentence,
        "generation_tier": _generation_tier(use_premium_spec),
    }


def produce_sentence(
    db: FirestoreClient,
    uid: str,
    params: dict,
    *,
    use_premium_spec: bool,
    estimated_vocab: int,
    cache_only: bool = False,
    select_retry: int = 1,
    lang: str = "ja",
) -> tuple[dict, list[str], str, bool] | None:
    """単語選定 → キャッシュ/LLM → generation_tier 付与までの生成コア。

    通常生成（generateThaiSentence）と毎日配信（deliverDailySentence）の共通経路。
    free はキャッシュ優先。cache_only=True（配信のfree経路）ではキャッシュミス時に
    select_retry 回までターゲット語を引き直し、LLM は呼ばない。

    Returns:
        (例文, target_words, 採用テーマ, キャッシュ由来か)。
        cache_only でキャッシュに当たらなければ None。
    """
    use_premium_prompt = use_premium_prompt_for_vocab(use_premium_spec, estimated_vocab)
    target_words: list[str] = []
    chosen_topic = ""
    for _ in range(max(1, select_retry)):
        target_words, chosen_topic = _select_target_words_with_topic(
            db,
            uid,
            params,
            is_premium=use_premium_prompt,
            estimated_vocab=estimated_vocab,
        )
        # free 例文バンク（GCS）は言語ごとに事前生成したもの（設計 §3.4）。
        # その言語のバンクがまだ無ければ空で返るので、下の LLM 生成へ落ちる。
        # cache_only（毎日配信の free 経路）でバンクが無ければ配信しない。
        if not use_premium_spec:
            cached = pick_free_sentence(target_words[0], lang, topic=chosen_topic)
            if cached is not None:
                return (
                    _attach_generation_tier(cached, use_premium_spec),
                    target_words,
                    chosen_topic,
                    True,
                )
        if not cache_only:
            break

    if cache_only:
        return None

    sentence = generate_sentence(
        {**params, "topic": chosen_topic},
        use_premium_spec,
        target_words=target_words,
        estimated_vocab=estimated_vocab,
        lang=lang,
    )
    return (
        _attach_generation_tier(sentence, use_premium_spec),
        target_words,
        chosen_topic,
        False,
    )


def _match_key_word(word_text: str, key_word: str) -> bool:
    w = word_text.strip()
    k = key_word.strip()
    return w == k or w == k + "ๆ" or w + "ๆ" == k


def _get_key_word_pronunciation(sentence: dict, key_word: str) -> str:
    for word in sentence.get("word_breakdown", []):
        if _match_key_word(word.get("word", ""), key_word):
            return word.get("pronunciation", "").strip()
    return ""


def _get_key_word_meaning(sentence: dict, key_word: str) -> str:
    for word in sentence.get("word_breakdown", []):
        if _match_key_word(word.get("word", ""), key_word):
            return word.get("meaning", "").strip()
    return ""


def _build_sentence_data(
    sentence: dict,
    key_word: str,
    *,
    use_premium_spec: bool,
) -> dict:
    return {
        "thai_text": sentence["thai_text"],
        "pronunciation": sentence.get("pronunciation", ""),
        "japanese_translation": sentence["japanese_translation"],
        "word_breakdown": sentence.get("word_breakdown", []),
        "context": sentence.get("context", {}),
        "created_at": firestore.firestore.SERVER_TIMESTAMP,
        "key_word": key_word,
        "key_word_pronunciation": _get_key_word_pronunciation(sentence, key_word),
        "key_word_meaning": _get_key_word_meaning(sentence, key_word),
        "generation_tier": _generation_tier(use_premium_spec),
    }


def _build_sentence_commit_update(
    user_data: dict,
    decrement_count: int,
) -> dict:
    """例文コミット時の users ドキュメント更新内容を組み立てる。

    トライアルは期間制なので、消費するのは通常クォータ（remaining_sentences）だけ。
    """
    return {
        "remaining_sentences": firestore.firestore.Increment(-decrement_count),
        "daily_sentence_generated": True,
        "last_active_at": firestore.firestore.SERVER_TIMESTAMP,
        "last_sentence_generated_at": firestore.firestore.SERVER_TIMESTAMP,
        "sentence_generated_count": firestore.firestore.Increment(decrement_count),
        **(
            {"first_generated_at": firestore.firestore.SERVER_TIMESTAMP}
            if "first_generated_at" not in user_data
            else {}
        ),
    }


@transactional
def _commit_sentences_transaction(
    transaction,
    user_ref,
    sentence_writes: list[tuple],
    decrement_count: int,
) -> None:
    user_snapshot = user_ref.get(transaction=transaction)
    user_data = (user_snapshot.to_dict() or {}) if user_snapshot.exists else {}
    remaining = user_data.get("remaining_sentences", 0)
    if remaining < decrement_count:
        raise RuntimeError("QUOTA_EXCEEDED")

    for sentence_ref, sentence_data in sentence_writes:
        transaction.set(sentence_ref, sentence_data)

    transaction.update(
        user_ref,
        _build_sentence_commit_update(user_data, decrement_count),
    )


def _ensure_user_quota(user_ref) -> dict:
    """users/{uid} doc が無い場合に初期クォータを冪等に付与し、その内容を返す。

    onUserCreate トリガー（JS）と同じ初期値を使う。merge=True なので、万一トリガーと
    競合しても既存フィールドを壊さない。値は constants.py（= quota.ts）で一元管理。
    """
    initial = {
        # 付与直後はトライアル中なので premium と同じ回数を出す。
        "remaining_sentences": PREMIUM_DAILY_SENTENCES,
        "remaining_quizzes": PREMIUM_DAILY_QUIZZES,
        "daily_sentence_generated": False,
        # 期限はクォータのリセット境界（JST 0:00）に揃える。utils/premium.ts と同じ規則。
        "premium_trial_expires_at": _ceil_to_jst_midnight(
            datetime.now(timezone.utc) + timedelta(days=PREMIUM_TRIAL_DAYS)
        ),
        # 旧クライアント（〜1.3.15）がテーマを消さないための凍結値。減らさない。
        "premium_trial_remaining": PREMIUM_TRIAL_SENTENCES,
    }
    user_ref.set(initial, merge=True)
    print(f"Initial quota set (fallback) for user {user_ref.id}")
    return dict(initial)


# 全環境で常駐させない。以前は prod のみ min=1 にしてコールドスタート
# （当時 p90 26.7秒）を隠していたが、2026-07-31 に重い import を排除して
# コールドが 10.6秒（ウォームは 7〜8秒）まで下がったため不要になった。
# 常駐アイドル課金は prod 実測で ¥70/日（月約2,100円）かかっていた。
_MIN_INSTANCES = 0


@https_fn.on_call(
    region="asia-northeast1",
    memory=2048,
    # NLP のインポート・後処理は nlp_worker.py の子プロセスで走る。
    # 親（LLM 呼び出し）と子を実際に並列で動かすため 2 vCPU が要る。
    # デフォルトの "gcf_gen1" は 2048MB では 1 vCPU。
    cpu=2,
    timeout_sec=120,
    concurrency=10,
    min_instances=_MIN_INSTANCES,
)
def generateThaiSentence(req: https_fn.CallableRequest) -> dict:
    start_time = time.time()
    response: dict = {"success": False}

    log_data = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "userId": req.auth.uid if req.auth else "anonymous",
        "requestedTopic": (req.data or {}).get("topic", "random"),
        # 訳文の言語。旧クライアントは送ってこないので ja に落ちる。
        "lang": resolve_lang(req.data),
        # App Check は現状 UNENFORCED（enforce_app_check=False のまま）。
        # 未証明リクエストの割合がここで測れるので、十分下がってから
        # enforce_app_check=True に切り替える。旧クライアントは App Check
        # トークンを送らないため、先に強制すると弾かれる。
        "appCheck": bool(req.app),
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

        assert req.auth.uid is not None
        uid: str = req.auth.uid
        print(f"Request started: {log_data}")

        db = firestore.client()
        user_ref = db.collection("users").document(uid)
        user_doc = user_ref.get()  # type: ignore[union-attr]
        user_data = (
            (user_doc.to_dict() or {})  # type: ignore[union-attr]
            if user_doc.exists  # type: ignore[union-attr]
            else {}
        )
        # 主経路は onUserCreate トリガーだが、doc 欠損（トリガー失敗・削除済み・
        # トリガー導入前ユーザー）のまま生成されると remaining_sentences=0 で
        # QUOTA_EXCEEDED になる。ここで冪等に初期クォータを付与して自己回復する。
        #
        # doc の有無ではなくクォータフィールドの有無で判定すること。孤児doc掃除
        # （dailyBatch）で doc が消えた後、updateUvm 等が merge=True でクイズ系
        # フィールドだけの部分docを作り直すケースがあり、doc は存在するのに
        # クォータだけ無い状態で永久に QUOTA_EXCEEDED になる。
        if "remaining_sentences" not in user_data:
            user_data = {**user_data, **_ensure_user_quota(user_ref)}  # type: ignore[union-attr]

        tier = user_data.get("tier", "free")
        is_premium = tier == "premium"

        # プレミアム体験トライアル: 期間中は premium ロジック
        # （テーマ選択・premiumプロンプト・語彙上限なし）で出す。
        trial_active = _resolve_trial_active(
            is_premium=is_premium,
            trial_expires_at=_trial_expires_at(user_data),
            now=datetime.now(timezone.utc),
        )

        # 生成スペック・テーマ採用は tier または トライアルで premium 相当とする
        effective_premium = is_premium or trial_active
        use_premium_spec = effective_premium

        remaining = user_data.get("remaining_sentences", 0)
        if remaining <= 0:
            log_data["error"] = "QUOTA_EXCEEDED"
            log_data["remainingSentences"] = remaining
            print(f"Quota exceeded: {log_data}")
            response["error"] = {
                "code": "QUOTA_EXCEEDED",
                "message": "この時間帯の例文生成上限に達しました",
            }
            return response

        params = _effective_generation_params(
            req.data or {},
            is_premium=effective_premium,
        )
        lang = log_data["lang"]
        estimated_vocab = _get_capped_estimated_vocab(user_data, use_premium_spec)
        produced = produce_sentence(
            db,
            uid,
            params,
            use_premium_spec=use_premium_spec,
            estimated_vocab=estimated_vocab,
            lang=lang,
        )
        if produced is None:  # cache_only=False では起きない
            raise RuntimeError("sentence generation returned nothing")
        sentence, target_words, chosen_topic, from_cache = produced
        log_data["uvmWords"] = len(target_words)
        log_data["chosenTopic"] = chosen_topic
        if from_cache:
            log_data["source"] = "cached"

        freq_rank = get_freq_rank()

        processing_time = int((time.time() - start_time) * 1000)
        log_data["success"] = True
        log_data["processingTimeMs"] = processing_time

        def _uvm_work() -> None:
            try:
                _register_sentence_exposure(db, uid, sentence, target_words)
            except Exception as exc:
                print(f"register_sentence_exposure failed: {exc}")

            try:
                max_vocab = None if is_premium else FREE_TIER_MAX_VOCAB
                sync_estimated_vocab(db, uid, freq_rank, max_vocab=max_vocab)
            except Exception as exc:
                print(f"sync_estimated_vocab failed: {exc}")

        uvm_thread = threading.Thread(target=_uvm_work, name="uvm-post")
        uvm_thread.start()

        try:
            sentence_data = _build_sentence_data(
                sentence,
                target_words[0],
                use_premium_spec=use_premium_spec,
            )
            sentence_ref = (
                db.collection("users").document(uid).collection("sentences").document()
            )
            transaction = db.transaction()
            _commit_sentences_transaction(
                transaction,
                user_ref,
                [(sentence_ref, sentence_data)],
                1,
            )
        except Exception as exc:
            print(f"Failed to save sentence to Firestore: {exc}")
            uvm_thread.join()
            raise

        response["success"] = True
        sentence["target_words"] = target_words
        response["data"] = sentence

        if not use_premium_spec:
            elapsed = time.time() - start_time
            if elapsed < 7:
                time.sleep(7 - elapsed)

        uvm_thread.join()

        print(f"Request completed successfully: {log_data}")
        return response

    except Exception as exc:
        processing_time = int((time.time() - start_time) * 1000)
        log_data["success"] = False
        log_data["processingTimeMs"] = processing_time
        error_msg = str(exc)
        log_data["errorMessage"] = error_msg

        if "QUOTA_EXCEEDED" in error_msg:
            response["error"] = {
                "code": "QUOTA_EXCEEDED",
                "message": "この時間帯の例文生成上限に達しました",
            }
        elif "SECRET_MANAGER_ERROR" in error_msg:
            response["error"] = {
                "code": "INTERNAL",
                "message": "Failed to retrieve API configuration",
            }
        elif "LLM_API_ERROR" in error_msg:
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
