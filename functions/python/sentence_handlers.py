import random
import time
from datetime import datetime, timezone

from firebase_admin import firestore
from firebase_functions import https_fn  # type: ignore[attr-defined]
from google.cloud.firestore_v1.client import Client as FirestoreClient
from google.cloud.firestore_v1 import transactional

try:
    from .constants import FREE_TIER_MAX_VOCAB, FREE_TOPICS, TOPICS
    from .embeddings import find_best_topic
    from .prompts import gate_topics_for_vocab
    from .runtime import initialize_firebase_app
    from .sentence_service import (
        generate_sentence,
        generate_sentences_batch,
        get_freq_rank,
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
    from constants import FREE_TIER_MAX_VOCAB, FREE_TOPICS, TOPICS
    from embeddings import find_best_topic
    from prompts import gate_topics_for_vocab
    from runtime import initialize_firebase_app
    from sentence_service import (
        generate_sentence,
        generate_sentences_batch,
        get_freq_rank,
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
        "created_at": firestore.firestore.SERVER_TIMESTAMP,
        "key_word": key_word,
        "generation_tier": _generation_tier(use_premium_spec),
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
        {
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
        },
    )


@https_fn.on_call(
    region="asia-northeast1", memory=2048, timeout_sec=120, concurrency=10
)
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

        assert req.auth.uid is not None
        uid: str = req.auth.uid
        print(f"Request started: {log_data}")

        db = firestore.client()
        user_ref = db.collection("users").document(uid)
        user_doc = user_ref.get()  # type: ignore[union-attr]
        user_data = (user_doc.to_dict() or {}) if user_doc.exists else {}  # type: ignore[union-attr]

        tier = user_data.get("tier", "free")
        is_premium = tier == "premium"

        # 初回生成はpremium相当のスペックで出力
        is_first_generation = user_data.get("is_first_generation", False) is True
        use_premium_spec = is_premium or is_first_generation
        if is_first_generation:
            log_data["firstGeneration"] = True

        remaining = user_data.get("remaining_sentences", 0)
        if remaining <= 0:
            response["error"] = {
                "code": "QUOTA_EXCEEDED",
                "message": "この時間帯の例文生成上限に達しました",
            }
            return response

        params = req.data or {}
        estimated_vocab = _get_capped_estimated_vocab(user_data, use_premium_spec)
        target_words, chosen_topic = _select_target_words_with_topic(
            db,
            uid,
            params,
            is_premium=use_premium_spec,
            estimated_vocab=estimated_vocab,
        )
        params["topic"] = chosen_topic
        log_data["uvmWords"] = len(target_words)
        log_data["chosenTopic"] = chosen_topic

        sentence = generate_sentence(
            params,
            use_premium_spec,
            target_words=target_words,
            estimated_vocab=estimated_vocab,
        )
        sentence = _attach_generation_tier(sentence, use_premium_spec)

        processing_time = int((time.time() - start_time) * 1000)
        log_data["success"] = True
        log_data["processingTimeMs"] = processing_time

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
            raise

        response["success"] = True
        sentence["target_words"] = target_words
        response["data"] = sentence

        # 初回生成フラグをクリア（残クォータが0になった時点）
        if is_first_generation and remaining <= 1:
            user_ref.update({"is_first_generation": firestore.firestore.DELETE_FIELD})

        # UVM 露出登録（free/premium 共通）
        try:
            log_data["uvmMatchedWords"] = _register_sentence_exposure(
                db,
                uid,
                sentence,
                target_words,
            )
        except Exception as exc:
            print(f"register_sentence_exposure failed: {exc}")
        # vocab_count / estimated_vocab を同期
        try:
            freq_rank = get_freq_rank()
            sync_estimated_vocab(db, uid, freq_rank)
        except Exception as exc:
            print(f"sync_estimated_vocab failed: {exc}")

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


@https_fn.on_call(region="asia-northeast1", memory=2048, timeout_sec=300)
def generateBatchSentences(req: https_fn.CallableRequest) -> dict:
    """残りクォータ分の例文を一括並列生成する。"""
    start_time = time.time()
    response: dict = {"success": False}
    log_data = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "userId": req.auth.uid if req.auth else "anonymous",
    }

    try:
        if not req.auth:
            response["error"] = {
                "code": "UNAUTHENTICATED",
                "message": "User must be authenticated",
            }
            return response

        assert req.auth.uid is not None
        uid: str = req.auth.uid
        db = firestore.client()
        user_ref = db.collection("users").document(uid)
        user_doc = user_ref.get()  # type: ignore[union-attr]
        user_data = (user_doc.to_dict() or {}) if user_doc.exists else {}  # type: ignore[union-attr]

        tier = user_data.get("tier", "free")
        is_premium = tier == "premium"

        # 初回生成はpremium相当のスペックで出力
        is_first_generation = user_data.get("is_first_generation", False) is True
        use_premium_spec = is_premium or is_first_generation
        if is_first_generation:
            log_data["firstGeneration"] = True

        remaining = user_data.get("remaining_sentences", 0)
        if remaining <= 0:
            response["error"] = {
                "code": "QUOTA_EXCEEDED",
                "message": "この時間帯の例文生成上限に達しました",
            }
            return response

        count = remaining
        estimated_vocab = _get_capped_estimated_vocab(user_data, use_premium_spec)
        log_data["batchCount"] = count

        # 表示件数に応じて必要数ぶんの key_word を一括選定し、表示順はシャッフルする
        selected_words, chosen_topic = _select_target_words_with_topic(
            db,
            uid,
            {},
            is_premium=use_premium_spec,
            estimated_vocab=estimated_vocab,
            count=count,
        )
        random.shuffle(selected_words)
        all_target_words = [[word] for word in selected_words]

        # 各単語ごとにテーマを選定（embedding → ランダムフォールバック）
        # 重複テーマは別のテーマに差し替えて多様性を確保
        topic_candidates = TOPICS if use_premium_spec else FREE_TOPICS
        topics_pool = gate_topics_for_vocab(topic_candidates, estimated_vocab)
        all_topics = []
        used_topics: set[str] = set()
        for word in selected_words:
            topic = find_best_topic(word, topics_pool)
            if not topic or topic in used_topics:
                available = [t for t in topics_pool if t not in used_topics]
                if not available:
                    available = topics_pool
                topic = random.choice(available)
            all_topics.append(topic)
            used_topics.add(topic)

        count = len(all_target_words)
        log_data["uvmWords"] = sum(len(tw) for tw in all_target_words)
        log_data["chosenTopics"] = all_topics

        # 並列生成
        sentences = generate_sentences_batch(
            count,
            is_premium=use_premium_spec,
            all_target_words=all_target_words,
            all_topics=all_topics,
            estimated_vocab=estimated_vocab,
        )
        for i, sentence in enumerate(sentences):
            sentence["target_words"] = all_target_words[i]
        sentences = [
            _attach_generation_tier(sentence, use_premium_spec)
            for sentence in sentences
        ]

        generated_count = len(sentences)
        log_data["generatedCount"] = generated_count

        if generated_count == 0:
            response["error"] = {
                "code": "API_ERROR",
                "message": "Failed to generate sentences",
            }
            return response

        sentence_writes: list[tuple] = []
        for i, sentence in enumerate(sentences):
            tw = all_target_words[i]
            sentence_data = _build_sentence_data(
                sentence,
                tw[0],
                use_premium_spec=use_premium_spec,
            )
            sentence_ref = (
                db.collection("users").document(uid).collection("sentences").document()
            )
            sentence_writes.append((sentence_ref, sentence_data))

        transaction = db.transaction()
        _commit_sentences_transaction(
            transaction,
            user_ref,
            sentence_writes,
            generated_count,
        )

        # 初回生成フラグをクリア
        if is_first_generation:
            user_ref.update({"is_first_generation": firestore.firestore.DELETE_FIELD})

        # UVM 露出登録
        try:
            for i, sentence in enumerate(sentences):
                tw = all_target_words[i]
                _register_sentence_exposure(db, uid, sentence, tw)
        except Exception as exc:
            print(f"register_sentence_exposure failed: {exc}")

        # vocab_count 同期
        try:
            freq_rank = get_freq_rank()
            sync_estimated_vocab(db, uid, freq_rank)
        except Exception as exc:
            print(f"sync_estimated_vocab failed: {exc}")

        processing_time = int((time.time() - start_time) * 1000)
        log_data["processingTimeMs"] = processing_time
        print(f"Batch generation completed: {log_data}")

        response["success"] = True
        response["data"] = {"sentences": sentences, "generated_count": generated_count}
        return response

    except Exception as exc:
        processing_time = int((time.time() - start_time) * 1000)
        log_data["processingTimeMs"] = processing_time
        log_data["errorMessage"] = str(exc)
        print(f"Batch generation failed: {log_data}")

        error_msg = str(exc)
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
                "message": "Failed to generate sentences",
            }
        else:
            response["error"] = {
                "code": "UNKNOWN",
                "message": "An unexpected error occurred",
            }
        return response
