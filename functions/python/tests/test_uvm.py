from pathlib import Path
import sys
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from uvm import (
    ALPHA_CORRECT_MAX_TOP,
    ALPHA_CORRECT_MIN,
    ALPHA_INCORRECT_MIN,
    ALPHA_EXPOSURE,
    FREQ_BAND_HALF,
    NEW_WORD_P,
    P_MAX,
    P_MIN,
    RANK_SCALE_REF,
    batch_update_uvm,
    get_exposed_words,
    get_session_words,
    register_exposure,
    update_p,
)


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


def test_register_exposure_creates_unknown_word_when_target() -> None:
    db = FakeDb()

    register_exposure(db, "user-1", ["น้ำ"], target_words=["น้ำ"])

    doc = db.store["user-1"]["น้ำ"]
    assert doc["p"] == NEW_WORD_P
    assert doc["quiz_attempts"] == 0


def test_register_exposure_skips_unknown_word_when_not_target() -> None:
    db = FakeDb()

    register_exposure(db, "user-1", ["น้ำ"])

    assert "น้ำ" not in db.store.get("user-1", {})


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

    # 1回目: target_words 指定で新規作成
    register_exposure(db, "user-1", ["น้ำ"], target_words=["น้ำ"])
    # 2回目: 登録済みなので P 更新
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
    # estimated_vocab=50: band=[20, 80], gap_scan=[0, 20)
    # 全語P>0 → ギャップなし → band内からランダム選出
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
            "in-band-low": 20,
            "in-band-high": 50,
            "out-band": 81,
        },
        topic="fixed-topic",
        count=2,
        estimated_vocab=50,
    )

    assert set(words) == {"in-band-low", "in-band-high"}
    assert chosen_topic == "fixed-topic"


def test_get_session_words_prioritizes_gap_unregistered_word() -> None:
    # estimated_vocab=100: band_boundary=70, gap_scan=[0, 70)
    # rank=50 は gap zone 内かつ UVM未登録 → 優先選出
    db = FakeDb(
        {
            "user-1": {
                "band-word": {"p": 0.3},
            }
        }
    )

    words, _ = get_session_words(
        db,
        "user-1",
        {
            "gap-unregistered": 50,
            "band-word": 80,
        },
        topic="fixed-topic",
        count=1,
        estimated_vocab=100,
    )

    assert words == ["gap-unregistered"]


def test_get_session_words_prioritizes_p_zero_gap_candidate() -> None:
    # estimated_vocab=100: gap zone に P=0 の語 → 優先選出
    db = FakeDb(
        {
            "user-1": {
                "gap-zero": {"p": 0.0},
                "band-word": {"p": 0.1},
            }
        }
    )

    words, _ = get_session_words(
        db,
        "user-1",
        {
            "gap-zero": 50,
            "band-word": 80,
        },
        topic="fixed-topic",
        count=1,
        estimated_vocab=100,
    )

    assert words == ["gap-zero"]


def test_get_session_words_falls_back_to_band_when_no_gap() -> None:
    # estimated_vocab=100: gap zone 内は全語P>0 → band内からランダム選出
    db = FakeDb(
        {
            "user-1": {
                "gap-known": {"p": 0.8},
                "band-word": {"p": 0.3},
            }
        }
    )

    words, _ = get_session_words(
        db,
        "user-1",
        {
            "gap-known": 50,
            "band-word": 80,
        },
        topic="fixed-topic",
        count=1,
        estimated_vocab=100,
    )

    assert words == ["band-word"]


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


# ---------------------------------------------------------------------------
# 境界値分析: update_p
# ---------------------------------------------------------------------------

def test_update_p_clips_to_p_max_on_correct() -> None:
    """P=P_MAXで正解してもP_MAXを超えない"""
    result = update_p(P_MAX, True, 0)
    assert result == P_MAX


def test_update_p_p_min_unchanged_on_incorrect() -> None:
    """P=0.0で不正解: p*(1-alpha)=0.0 → P_MIN=0.0のまま"""
    result = update_p(0.0, False, 0)
    assert result == P_MIN


def test_update_p_rank0_uses_alpha_correct_max_top() -> None:
    """rank=0 → scale=1.0 → alpha_max=ALPHA_CORRECT_MAX_TOP, quiz_attempts=0でαがmax"""
    p = 0.1
    result = update_p(p, True, 0, rank=0)
    expected = p + ALPHA_CORRECT_MAX_TOP * (1 - p)
    assert abs(result - expected) < 1e-9


def test_update_p_rank_none_equals_rank_scale_ref() -> None:
    """rank=None(scale=0.5) と rank=RANK_SCALE_REF(scale=0.5) は同じ結果"""
    p = 0.5
    assert update_p(p, True, 0, rank=None) == update_p(p, True, 0, rank=RANK_SCALE_REF)
    assert update_p(p, False, 5, rank=None) == update_p(p, False, 5, rank=RANK_SCALE_REF)


def test_update_p_correct_alpha_converges_to_min() -> None:
    """正解: quiz_attemptsが十分大きいとαがALPHA_CORRECT_MINに収束"""
    p = 0.5
    result = update_p(p, True, 1000)
    expected = p + ALPHA_CORRECT_MIN * (1 - p)
    assert abs(result - expected) < 1e-6


def test_update_p_incorrect_alpha_converges_to_min() -> None:
    """不正解: quiz_attemptsが十分大きいとαがALPHA_INCORRECT_MINに収束"""
    p = 0.5
    result = update_p(p, False, 1000)
    expected = p - ALPHA_INCORRECT_MIN * p
    assert abs(result - expected) < 1e-6


def test_update_p_correct_delta_larger_than_incorrect_delta() -> None:
    """正解のP増分 > 不正解のP減分（意図的な非対称性の確認）"""
    p = 0.5
    correct_delta = update_p(p, True, 0) - p
    incorrect_delta = p - update_p(p, False, 0)
    assert correct_delta > incorrect_delta > 0


# ---------------------------------------------------------------------------
# 境界値分析: get_session_words × estimated_vocab
# ---------------------------------------------------------------------------

def test_get_session_words_estimated_vocab_0_no_gap_scan() -> None:
    """estimated_vocab=0: band_boundary=0 → ギャップスキャンなし, band=[0, FREQ_BAND_HALF]"""
    db = FakeDb()
    in_band = "word-aa"    # rank=5  (band内)
    out_band = "word-bb"   # rank=FREQ_BAND_HALF+1 (band外)
    freq_rank = {in_band: 5, out_band: FREQ_BAND_HALF + 1}

    words, _ = get_session_words(db, "user-1", freq_rank, topic="t", count=1, estimated_vocab=0)

    assert words == [in_band]


def test_get_session_words_estimated_vocab_29_no_gap_scan() -> None:
    """estimated_vocab=29(=FREQ_BAND_HALF-1): band_boundary=0 → ギャップスキャンなし"""
    db = FakeDb()
    ev = FREQ_BAND_HALF - 1  # 29
    freq_rank = {"word-aa": 0, "word-bb": ev}

    words, _ = get_session_words(db, "user-1", freq_rank, topic="t", count=2, estimated_vocab=ev)

    # ギャップスキャンなし → どちらもバンド内（band=[0, 59]）
    assert set(words) == {"word-aa", "word-bb"}


def test_get_session_words_estimated_vocab_30_no_gap_scan() -> None:
    """estimated_vocab=30(=FREQ_BAND_HALF): band_boundary=max(0,0)=0 → ギャップスキャンなし"""
    db = FakeDb()
    ev = FREQ_BAND_HALF  # 30
    freq_rank = {"word-aa": 0, "word-bb": ev}

    words, _ = get_session_words(db, "user-1", freq_rank, topic="t", count=2, estimated_vocab=ev)

    assert set(words) == {"word-aa", "word-bb"}


def test_get_session_words_estimated_vocab_31_gap_scan_starts() -> None:
    """estimated_vocab=31(=FREQ_BAND_HALF+1): band_boundary=1 → ギャップスキャン=[0,1)が有効"""
    db = FakeDb()  # UVM空 → rank=0語が未登録ギャップ候補
    ev = FREQ_BAND_HALF + 1  # 31
    freq_rank = {
        "gap-word": 0,    # ギャップスキャン範囲 [0,1) に該当
        "band-word": 10,  # バンド内
    }

    words, _ = get_session_words(db, "user-1", freq_rank, topic="t", count=1, estimated_vocab=ev)

    # rank=0の未登録語がギャップとして優先選出される
    assert words == ["gap-word"]


def test_get_session_words_estimated_vocab_31_gap_known_falls_back_to_band() -> None:
    """estimated_vocab=31: ギャップ候補(rank=0)がP>0なら→バンドへフォールバック"""
    db = FakeDb({"user-1": {"gap-word": {"p": 0.8}}})
    ev = FREQ_BAND_HALF + 1  # 31
    freq_rank = {
        "gap-word": 0,
        "band-word": 10,
    }

    words, _ = get_session_words(db, "user-1", freq_rank, topic="t", count=1, estimated_vocab=ev)

    assert words == ["band-word"]


# ---------------------------------------------------------------------------
# hint_level 後方互換性
# ---------------------------------------------------------------------------

def test_batch_update_uvm_without_hint_level_uses_full_multiplier() -> None:
    """旧クライアント: hint_level キーなし → multiplier=1.0 でP更新される"""
    p0 = 0.1
    db = FakeDb(
        {"user-1": {"ไป": {"word": "ไป", "p": p0, "quiz_attempts": 0, "last_seen": 0.0, "last_result": False}}},
        {"user-1": {"estimated_vocab": 0}},
    )

    batch_update_uvm(
        db, "user-1",
        [{"word": "ไป", "is_correct": True}],  # hint_level なし
        freq_rank={"ไป": 1},
    )

    p_new = db.store["user-1"]["ไป"]["p"]
    p_expected = update_p(p0, True, 0, rank=1, hint_multiplier=1.0)
    assert abs(p_new - p_expected) < 1e-9


def test_batch_update_uvm_hint_level_null_uses_full_multiplier() -> None:
    """旧クライアント: hint_level=null → multiplier=1.0 でP更新される"""
    p0 = 0.1
    db = FakeDb(
        {"user-1": {"ไป": {"word": "ไป", "p": p0, "quiz_attempts": 0, "last_seen": 0.0, "last_result": False}}},
        {"user-1": {"estimated_vocab": 0}},
    )

    batch_update_uvm(
        db, "user-1",
        [{"word": "ไป", "is_correct": True, "hint_level": None}],
        freq_rank={"ไป": 1},
    )

    p_new = db.store["user-1"]["ไป"]["p"]
    p_expected = update_p(p0, True, 0, rank=1, hint_multiplier=1.0)
    assert abs(p_new - p_expected) < 1e-9


def test_batch_update_uvm_hint_level_1_reduces_p_change() -> None:
    """hint_level=1 → multiplier=0.5 でP増分がヒントなしの半分になる"""
    p0 = 0.1
    rank = 600

    p_no_hint = update_p(p0, True, 0, rank=rank, hint_multiplier=1.0)
    p_hint1   = update_p(p0, True, 0, rank=rank, hint_multiplier=0.5)

    delta_no_hint = p_no_hint - p0
    delta_hint1   = p_hint1   - p0

    assert abs(delta_hint1 - delta_no_hint * 0.5) < 1e-9


def test_batch_update_uvm_hint_level_2_reduces_p_change() -> None:
    """hint_level=2 → multiplier=0.25 でP増分がヒントなしの1/4になる"""
    p0 = 0.1
    rank = 600

    p_no_hint = update_p(p0, True, 0, rank=rank, hint_multiplier=1.0)
    p_hint2   = update_p(p0, True, 0, rank=rank, hint_multiplier=0.25)

    delta_no_hint = p_no_hint - p0
    delta_hint2   = p_hint2   - p0

    assert abs(delta_hint2 - delta_no_hint * 0.25) < 1e-9


def test_update_p_hint_multiplier_default_matches_explicit_1() -> None:
    """hint_multiplier省略 == hint_multiplier=1.0（デフォルト値の後方互換確認）"""
    p = 0.3
    assert update_p(p, True, 3, rank=500) == update_p(p, True, 3, rank=500, hint_multiplier=1.0)
    assert update_p(p, False, 3, rank=500) == update_p(p, False, 3, rank=500, hint_multiplier=1.0)
