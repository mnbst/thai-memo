from pathlib import Path
import sys
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from uvm import ALPHA_EXPOSURE, NEW_WORD_P, P_MAX, batch_update_uvm, get_exposed_words, get_session_words, register_exposure, update_p


class FakeDocSnapshot:
    def __init__(self, doc_id: str, data: dict | None) -> None:
        self.id = doc_id
        self._data = data

    @property
    def exists(self) -> bool:
        return self._data is not None

    def to_dict(self) -> dict | None:
        return None if self._data is None else dict(self._data)


class FakeDocRef:
    def __init__(self, store: dict[str, dict], doc_id: str) -> None:
        self.store = store
        self.doc_id = doc_id

    def get(self) -> FakeDocSnapshot:
        return FakeDocSnapshot(self.doc_id, self.store.get(self.doc_id))


class FakeWordCollection:
    def __init__(self, store: dict[str, dict]) -> None:
        self.store = store

    def document(self, doc_id: str) -> FakeDocRef:
        return FakeDocRef(self.store, doc_id)

    def select(self, fields: list[str]) -> "FakeSelectedWordCollection":
        return FakeSelectedWordCollection(self.store, fields)


class FakeSelectedWordCollection:
    def __init__(self, store: dict[str, dict], fields: list[str]) -> None:
        self.store = store
        self.fields = fields

    def get(self) -> list[FakeDocSnapshot]:
        return [
            FakeDocSnapshot(
                doc_id,
                {field: data[field] for field in self.fields if field in data},
            )
            for doc_id, data in self.store.items()
        ]


class FakeUserDoc:
    def __init__(
        self,
        user_store: dict[str, dict],
        user_docs: dict[str, dict],
        uid: str,
    ) -> None:
        self.user_store = user_store
        self.user_docs = user_docs
        self.uid = uid

    def collection(self, name: str) -> FakeWordCollection:
        assert name == "uvm"
        return FakeWordCollection(self.user_store)

    def set(self, data: dict, merge: bool = False) -> None:
        if merge:
            self.user_docs.setdefault(self.uid, {}).update(data)
            return
        self.user_docs[self.uid] = dict(data)

    def get(self) -> FakeDocSnapshot:
        return FakeDocSnapshot(self.uid, self.user_docs.get(self.uid))


class FakeUsersCollection:
    def __init__(
        self,
        store: dict[str, dict[str, dict]],
        user_docs: dict[str, dict],
    ) -> None:
        self.store = store
        self.user_docs = user_docs

    def document(self, uid: str) -> FakeUserDoc:
        return FakeUserDoc(self.store.setdefault(uid, {}), self.user_docs, uid)


class FakeBatch:
    def __init__(self) -> None:
        self.operations: list[tuple[str, FakeDocRef, dict]] = []

    def update(self, doc_ref: FakeDocRef, data: dict) -> None:
        self.operations.append(("update", doc_ref, data))

    def set(self, doc_ref: FakeDocRef, data: dict) -> None:
        self.operations.append(("set", doc_ref, data))

    def commit(self) -> None:
        for op, doc_ref, data in self.operations:
            if op == "set":
                doc_ref.store[doc_ref.doc_id] = dict(data)
            else:
                doc_ref.store[doc_ref.doc_id].update(data)


class FakeDb:
    def __init__(
        self,
        store: dict[str, dict[str, dict]] | None = None,
        user_docs: dict[str, dict] | None = None,
    ) -> None:
        self.store = store or {}
        self.user_docs = user_docs or {}

    def collection(self, name: str) -> FakeUsersCollection:
        assert name == "users"
        return FakeUsersCollection(self.store, self.user_docs)

    def get_all(self, refs: list[FakeDocRef]) -> list[FakeDocSnapshot]:
        return [
            FakeDocSnapshot(ref.doc_id, ref.store.get(ref.doc_id))
            for ref in refs
        ]

    def batch(self) -> FakeBatch:
        return FakeBatch()


def test_get_exposed_words_filters_to_actual_sentence_words() -> None:
    sentence = {
        "word_breakdown": [
            {"word": "กิน"},
            {"word": "ข้าว"},
        ]
    }

    assert get_exposed_words(sentence, ["กิน", "น้ำ"]) == ["กิน"]


def test_get_exposed_words_counts_duplicate_occurrences_once_per_sentence() -> None:
    sentence = {
        "word_breakdown": [
            {"word": "กิน"},
            {"word": "ข้าว"},
            {"word": "กิน"},
        ]
    }

    assert get_exposed_words(sentence, ["กิน", "น้ำ"]) == ["กิน"]


def test_register_exposure_adds_alpha_for_existing_single_occurrence() -> None:
    db = FakeDb(
        {
            "user-1": {
                "กิน": {
                    "word": "กิน",
                    "p": 0.6,
                    "quiz_attempts": 1,
                    "last_seen": 123.0,
                    "last_result": True,
                }
            }
        }
    )

    register_exposure(db, "user-1", ["กิน"])

    doc = db.store["user-1"]["กิน"]
    # p = p + ALPHA_EXPOSURE * (1 - p)
    assert doc["p"] == 0.6 + ALPHA_EXPOSURE * (1 - 0.6)
    assert doc["last_seen"] > 123.0


def test_register_exposure_creates_unknown_word() -> None:
    db = FakeDb()

    register_exposure(db, "user-1", ["น้ำ"])

    doc = db.store["user-1"]["น้ำ"]
    assert doc["p"] == NEW_WORD_P
    assert doc["quiz_attempts"] == 0


def test_register_exposure_adds_alpha_for_duplicate_occurrences() -> None:
    db = FakeDb(
        {
            "user-1": {
                "กิน": {
                    "word": "กิน",
                    "p": 0.6,
                    "quiz_attempts": 1,
                    "last_seen": 123.0,
                    "last_result": True,
                }
            }
        }
    )

    register_exposure(db, "user-1", ["กิน", "กิน"])

    doc = db.store["user-1"]["กิน"]
    # p = p + ALPHA_EXPOSURE * (1 - p) を2回適用
    p1 = 0.6 + ALPHA_EXPOSURE * (1 - 0.6)
    expected_p = p1 + ALPHA_EXPOSURE * (1 - p1)
    assert doc["p"] == expected_p
    assert doc["last_seen"] > 123.0


def test_register_exposure_updates_p_on_second_call() -> None:
    db = FakeDb()

    register_exposure(db, "user-1", ["น้ำ"])
    register_exposure(db, "user-1", ["น้ำ"])

    doc = db.store["user-1"]["น้ำ"]
    # 1回目: 新規作成 (p=NEW_WORD_P), 2回目: p + ALPHA_EXPOSURE * (1 - p)
    expected_p = NEW_WORD_P + ALPHA_EXPOSURE * (1 - NEW_WORD_P)
    assert doc["p"] == expected_p


def test_update_p_alpha_decays_with_quiz_attempts() -> None:
    """quiz_attempts が増えるほど P の変化量が小さくなる"""
    base_p = 0.5

    # 正解: quiz_attempts=0 vs 20
    delta_first = update_p(base_p, True, 0) - base_p
    delta_many = update_p(base_p, True, 20) - base_p
    assert delta_first > delta_many > 0

    # 不正解: quiz_attempts=0 vs 20
    drop_first = base_p - update_p(base_p, False, 0)
    drop_many = base_p - update_p(base_p, False, 20)
    assert drop_first > drop_many > 0


def test_get_session_words_excludes_out_of_band_candidates() -> None:
    db = FakeDb(
        {
            "user-1": {
                "in-band-low": {"p": 0.8},
                "in-band-high": {"p": 0.9},
                "out-band": {"p": 0.01},
            }
        }
    )

    words, chosen_topic = get_session_words(
        db,
        "user-1",
        {
            "in-band-low": 10,
            "in-band-high": 20,
            "out-band": 41,
        },
        topic="fixed-topic",
        count=2,
        estimated_vocab=10,
    )

    assert words == ["in-band-low", "in-band-high"]
    assert chosen_topic == "fixed-topic"


def test_get_session_words_prioritizes_lower_p_within_band() -> None:
    db = FakeDb(
        {
            "user-1": {
                "low-p": {"p": 0.1},
                "high-p": {"p": 0.9},
            }
        }
    )

    words, _ = get_session_words(
        db,
        "user-1",
        {
            "low-p": 10,
            "high-p": 11,
        },
        topic="fixed-topic",
        count=2,
        estimated_vocab=10,
    )

    assert words == ["low-p", "high-p"]


def test_get_session_words_prioritizes_unknown_before_high_p_known_word() -> None:
    db = FakeDb(
        {
            "user-1": {
                "known": {"p": 0.8},
            }
        }
    )

    words, _ = get_session_words(
        db,
        "user-1",
        {
            "unknown": 10,
            "known": 11,
        },
        topic="fixed-topic",
        count=2,
        estimated_vocab=10,
    )

    assert words == ["unknown", "known"]


def test_get_session_words_uses_random_only_for_full_ties() -> None:
    db = FakeDb(
        {
            "user-1": {
                "left": {"p": 0.4},
                "right": {"p": 0.4},
            }
        }
    )

    with patch("uvm.random.random", side_effect=[0.9, 0.1]):
        words, _ = get_session_words(
            db,
            "user-1",
            {
                "left": 9,
                "right": 11,
            },
            topic="fixed-topic",
            count=2,
            estimated_vocab=10,
        )

    assert words == ["right", "left"]


def test_batch_update_uvm_syncs_counts_for_existing_word_updates() -> None:
    db = FakeDb(
        {
            "user-1": {
                "กิน": {
                    "word": "กิน",
                    "p": 0.65,
                    "quiz_attempts": 1,
                    "last_seen": 123.0,
                    "last_result": True,
                }
            }
        },
        {
            "user-1": {
                "estimated_vocab": 0,
            }
        },
    )

    batch_update_uvm(
        db,
        "user-1",
        [{"word": "กิน", "is_correct": True}],
        freq_rank={"กิน": 12},
    )

    # 1語(rank=12, p>0.5)→ スパースフォールバックで known_max_rank=12
    assert db.user_docs["user-1"]["estimated_vocab"] == 12
