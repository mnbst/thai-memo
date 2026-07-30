from pathlib import Path
import sys
from unittest.mock import patch
import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))


@pytest.fixture(autouse=True)
def _mock_topic_embedding():
    with patch("uvm.get_topic_embedding", return_value=None):
        yield

from uvm import (
    ALPHA_CORRECT_MAX_TOP,
    ALPHA_CORRECT_MIN,
    ALPHA_INCORRECT_MIN,
    ALPHA_EXPOSURE,
    GAP_SCAN_DEPTH,
    SCAN_AHEAD,
    LEARNING_CORRECT_MULTIPLIER,
    NEW_WORD_P,
    P_MAX,
    P_MIN,
    RANK_SCALE_REF,
    VOCAB_MAX_DELTA,
    batch_update_uvm,
    get_exposed_words,
    get_session_words,
    register_exposure,
    sync_estimated_vocab,
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


def test_get_session_words_excludes_out_of_scan_candidates() -> None:
    # estimated_vocab=50: scan=[25, 60]
    # scan外の語は選出されない
    db = FakeDb(
        {
            "user-1": {
                "in-scan-low": {"p": 0.8},
                "in-scan-high": {"p": 0.9},
                "out-scan": {"p": 0.01},
            }
        }
    )

    words, chosen_topic = get_session_words(
        db,
        "user-1",
        {
            "in-scan-low": 40,
            "in-scan-high": 50,
            "out-scan": 65,
        },
        topic="fixed-topic",
        count=2,
        estimated_vocab=50,
    )

    assert set(words) == {"in-scan-low", "in-scan-high"}
    assert chosen_topic == "fixed-topic"


def test_get_session_words_selects_unregistered_word() -> None:
    # estimated_vocab=100: scan=[75, 110]
    # rank=90 は scan 内かつ UVM未登録 → P=0として選出
    db = FakeDb(
        {
            "user-1": {
                "known-word": {"p": 0.3},
            }
        }
    )

    words, _ = get_session_words(
        db,
        "user-1",
        {
            "unregistered": 90,
            "known-word": 95,
        },
        topic="fixed-topic",
        count=1,
        estimated_vocab=100,
    )

    assert words == ["unregistered"]


def test_get_session_words_selects_p_zero_word() -> None:
    # estimated_vocab=100: scan=[75, 110], scan内に P=0 の語 → 選出
    db = FakeDb(
        {
            "user-1": {
                "zero-p": {"p": 0.0},
                "known-word": {"p": 0.1},
            }
        }
    )

    words, _ = get_session_words(
        db,
        "user-1",
        {
            "zero-p": 90,
            "known-word": 95,
        },
        topic="fixed-topic",
        count=1,
        estimated_vocab=100,
    )

    assert words == ["zero-p"]


def test_get_session_words_falls_back_to_weighted_when_all_known() -> None:
    # estimated_vocab=100: scan内の全語がP>0 → P低いほど選ばれやすい重み付き選出
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
            "low-p": 70,
            "high-p": 90,
        },
        topic="fixed-topic",
        count=1,
        estimated_vocab=100,
    )

    assert words[0] in {"low-p", "high-p"}


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

    # raw=12 だが current=0 → ダンパーで VOCAB_MAX_DELTA に制限
    assert db.user_docs["user-1"]["estimated_vocab"] == VOCAB_MAX_DELTA


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

def test_get_session_words_estimated_vocab_0() -> None:
    """estimated_vocab=0: scan=[0, SCAN_AHEAD]"""
    db = FakeDb()
    in_scan = "word-aa"     # rank=3 (scan内)
    out_scan = "word-bb"    # rank=SCAN_AHEAD+1 (scan外)
    freq_rank = {in_scan: 3, out_scan: SCAN_AHEAD + 1}

    words, _ = get_session_words(db, "user-1", freq_rank, topic="t", count=1, estimated_vocab=0)

    assert words == [in_scan]


def test_get_session_words_estimated_vocab_small() -> None:
    """estimated_vocab=10: scan=[0, 20] — 両語ともscan内"""
    db = FakeDb()
    freq_rank = {"word-aa": 0, "word-bb": 10}

    words, _ = get_session_words(db, "user-1", freq_rank, topic="t", count=2, estimated_vocab=10)

    assert set(words) == {"word-aa", "word-bb"}


def test_get_session_words_scan_high_boundary() -> None:
    """scan上限ちょうどの語は選出される"""
    db = FakeDb()
    ev = 50
    freq_rank = {"word-at-high": ev + SCAN_AHEAD, "word-over": ev + SCAN_AHEAD + 1}

    words, _ = get_session_words(db, "user-1", freq_rank, topic="t", count=1, estimated_vocab=ev)

    assert words == ["word-at-high"]


def test_get_session_words_rank_weighting_favors_higher_rank() -> None:
    """P=0の候補が複数ある場合、rankが高い語ほど選ばれやすい"""
    db = FakeDb()
    ev = 100
    freq_rank = {"low-rank": 66, "high-rank": 104}

    high_count = 0
    for _ in range(200):
        words, _ = get_session_words(db, "user-1", freq_rank, topic="t", count=1, estimated_vocab=ev)
        if words == ["high-rank"]:
            high_count += 1

    assert high_count > 100  # high-rank(104) が low-rank(66) より多く選ばれる


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


# ==================== quiz_type="learning" テスト ====================


def test_batch_update_uvm_learning_correct_reduces_p_increase() -> None:
    """quiz_type='learning' + 正解 → P増分は通常の10%程度に抑える"""
    p0 = 0.1
    db = FakeDb(
        {"user-1": {"ไป": {"word": "ไป", "p": p0, "quiz_attempts": 0, "last_seen": 0.0, "last_result": False}}},
        {"user-1": {"estimated_vocab": 0}},
    )

    batch_update_uvm(
        db, "user-1",
        [{"word": "ไป", "is_correct": True}],
        freq_rank={"ไป": 300},
        quiz_type="learning",
    )

    p_new = db.store["user-1"]["ไป"]["p"]
    p_expected = update_p(p0, True, 0, rank=300, hint_multiplier=LEARNING_CORRECT_MULTIPLIER)
    assert abs(p_new - p_expected) < 1e-9
    p_normal = update_p(p0, True, 0, rank=300, hint_multiplier=1.0)
    assert abs((p_new - p0) - (p_normal - p0) * 0.1) < 1e-9


def test_batch_update_uvm_learning_incorrect_unchanged() -> None:
    """quiz_type='learning' + 不正解 → 通常と同じP減少（learning減衰なし）"""
    p0 = 0.5
    db = FakeDb(
        {"user-1": {"ไป": {"word": "ไป", "p": p0, "quiz_attempts": 2, "last_seen": 0.0, "last_result": True}}},
        {"user-1": {"estimated_vocab": 0}},
    )

    batch_update_uvm(
        db, "user-1",
        [{"word": "ไป", "is_correct": False}],
        freq_rank={"ไป": 300},
        quiz_type="learning",
    )

    p_new = db.store["user-1"]["ไป"]["p"]
    p_expected = update_p(p0, False, 2, rank=300, hint_multiplier=1.0)
    assert abs(p_new - p_expected) < 1e-9


def test_batch_update_uvm_no_quiz_type_backward_compat() -> None:
    """quiz_type未指定（旧クライアント） → 通常のP更新"""
    p0 = 0.1
    db = FakeDb(
        {"user-1": {"ไป": {"word": "ไป", "p": p0, "quiz_attempts": 0, "last_seen": 0.0, "last_result": False}}},
        {"user-1": {"estimated_vocab": 0}},
    )

    batch_update_uvm(
        db, "user-1",
        [{"word": "ไป", "is_correct": True}],
        freq_rank={"ไป": 300},
    )

    p_new = db.store["user-1"]["ไป"]["p"]
    p_expected = update_p(p0, True, 0, rank=300, hint_multiplier=1.0)
    assert abs(p_new - p_expected) < 1e-9


def test_batch_update_uvm_learning_with_hint_stacks() -> None:
    """quiz_type='learning' + hint_level=1 → 両方の乗数が掛け合わされる"""
    p0 = 0.1
    db = FakeDb(
        {"user-1": {"ไป": {"word": "ไป", "p": p0, "quiz_attempts": 0, "last_seen": 0.0, "last_result": False}}},
        {"user-1": {"estimated_vocab": 0}},
    )

    batch_update_uvm(
        db, "user-1",
        [{"word": "ไป", "is_correct": True, "hint_level": 1}],
        freq_rank={"ไป": 300},
        quiz_type="learning",
    )

    p_new = db.store["user-1"]["ไป"]["p"]
    # hint_level=1 → 0.5, learning → ×0.1, 合計 0.05
    p_expected = update_p(p0, True, 0, rank=300, hint_multiplier=0.5 * LEARNING_CORRECT_MULTIPLIER)
    assert abs(p_new - p_expected) < 1e-9


# ---------------------------------------------------------------------------
# sync_estimated_vocab ダンパー
# ---------------------------------------------------------------------------

def test_sync_estimated_vocab_clamps_large_increase() -> None:
    """raw が current+30 でも VOCAB_MAX_DELTA に制限される"""
    current = 50
    # rank 70〜80 に P=0.9 の語を大量に配置 → estimate_vocab が大幅に上がる
    uvm_store: dict[str, dict] = {}
    freq_rank: dict[str, int] = {}
    for i in range(current + 20, current + 40):
        word = f"w{i}"
        freq_rank[word] = i
        uvm_store[word] = {"p": 0.95}

    db = FakeDb(
        {"user-1": uvm_store},
        {"user-1": {"estimated_vocab": current}},
    )

    sync_estimated_vocab(db, "user-1", freq_rank)

    new_ev = db.user_docs["user-1"]["estimated_vocab"]
    assert new_ev <= current + VOCAB_MAX_DELTA


def test_sync_estimated_vocab_clamps_large_decrease() -> None:
    """raw が current-30 でも -VOCAB_MAX_DELTA に制限される"""
    current = 100
    # rank 50〜60 に P=0.01 の語 → estimate_vocab が大幅に下がる
    uvm_store: dict[str, dict] = {}
    freq_rank: dict[str, int] = {}
    for i in range(current - 50, current - 30):
        word = f"w{i}"
        freq_rank[word] = i
        uvm_store[word] = {"p": 0.01}

    db = FakeDb(
        {"user-1": uvm_store},
        {"user-1": {"estimated_vocab": current}},
    )

    sync_estimated_vocab(db, "user-1", freq_rank)

    new_ev = db.user_docs["user-1"]["estimated_vocab"]
    assert new_ev >= current - VOCAB_MAX_DELTA
