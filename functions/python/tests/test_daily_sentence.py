from datetime import datetime, timedelta, timezone

import pytest

from daily_sentence import (
    TIER_MAX_MISSES,
    TIER_STOPPED,
    evaluate_response,
    is_due,
    local_date,
    local_hour,
    delivery_skip_reason,
    notify_utc_hour,
    should_deliver,
    uses_premium_trial,
)
import daily_sentence_handlers
from daily_sentence_handlers import (
    _commit_daily_sentence_body,
    _deliver_one,
    _DeliveryNotDue,
    _DeliveryStopped,
    build_notification_text,
)

NOW = datetime(2026, 7, 21, 1, 0, tzinfo=timezone.utc)  # JST 10:00
_FUTURE = NOW + timedelta(days=1)
_PAST = NOW - timedelta(seconds=1)


def _user(**overrides) -> dict:
    base = {
        "last_sentence_generated_at": NOW - timedelta(days=10),
        "fcm_token": "token",
        "remaining_sentences": 5,
        "daily_sentence_generated": False,
    }
    base.update(overrides)
    return base


def test_notify_utc_hour_matches_should_deliver_hour():
    """配信対象クエリの絞り込みが should_deliver のローカル時刻判定と一致すること。

    分単位オフセット（+5:30 / +5:45）でも現地の各時刻はUTCのいずれか1時刻に
    対応するため、絞り込みで取りこぼしが出ない。
    """
    for tz in [
        None,
        "Asia/Tokyo",
        "Asia/Bangkok",
        "Asia/Kolkata",  # +5:30
        "Asia/Kathmandu",  # +5:45
        "America/Los_Angeles",
        "Pacific/Chatham",  # +12:45
    ]:
        for preferred in range(24):
            user = _user(timezone=tz, preferred_generation_hour=preferred)
            utc_hour = notify_utc_hour(user, NOW)
            assert utc_hour is not None, (tz, preferred)
            assert should_deliver(user, NOW.replace(hour=utc_hour)), (tz, preferred)


def test_notify_utc_hour_returns_none_for_dst_gap():
    """DST春の切り替え日に存在しない現地時刻は None（既存値を維持させる）。"""
    dst_day = datetime(2026, 3, 8, 0, 0, tzinfo=timezone.utc)
    user = _user(timezone="America/Los_Angeles", preferred_generation_hour=2)
    assert notify_utc_hour(user, dst_day) is None


def test_notify_utc_hour_defaults():
    assert notify_utc_hour({}, NOW) == 1  # Asia/Tokyo 10時 = UTC 1時


def test_local_hour_falls_back_to_tokyo():
    assert local_hour(None, NOW) == 10
    assert local_hour("Not/AZone", NOW) == 10
    assert local_hour("America/New_York", NOW) == 21


def test_local_date_uses_user_timezone():
    assert local_date("Asia/Tokyo", NOW) == "2026-07-21"
    assert local_date("America/New_York", NOW) == "2026-07-20"


def test_is_due_first_time():
    assert is_due(_user(), NOW) is True


def test_is_due_respects_tier_interval():
    user = _user(notify_tier=2, last_notified_at=NOW - timedelta(days=9))
    assert is_due(user, NOW) is False
    user["last_notified_at"] = NOW - timedelta(days=10)
    assert is_due(user, NOW) is True


def test_is_due_false_when_stopped():
    assert is_due(_user(notify_tier=TIER_STOPPED), NOW) is False


def test_generation_resets_tier():
    user = _user(
        notify_tier=2,
        notify_tier_misses=2,
        last_notified_at=NOW - timedelta(days=10),
        last_sentence_generated_at=NOW - timedelta(days=1),
    )
    assert evaluate_response(user) == {"notify_tier": 0, "notify_tier_misses": 0}


def test_open_only_holds_tier_but_clears_misses():
    """開封は段階を戻さないが、無反応の連続カウントは0に戻す。"""
    user = _user(
        notify_tier=1,
        notify_tier_misses=2,
        last_notified_at=NOW - timedelta(days=3),
        last_opened_at=NOW - timedelta(days=2),
    )
    assert evaluate_response(user) == {"notify_tier": 1, "notify_tier_misses": 0}


def test_open_before_last_notification_is_not_a_response():
    """前回通知より古い開封は反応として数えない。"""
    user = _user(
        notify_tier=0,
        notify_tier_misses=1,
        last_notified_at=NOW - timedelta(days=1),
        last_opened_at=NOW - timedelta(days=5),
    )
    assert evaluate_response(user) == {"notify_tier": 0, "notify_tier_misses": 2}


def test_no_response_advances_tier_after_three_misses():
    user = _user(notify_tier=0, notify_tier_misses=0, last_notified_at=NOW - timedelta(days=1))
    for expected_misses in (1, 2):
        result = evaluate_response(user)
        assert result == {"notify_tier": 0, "notify_tier_misses": expected_misses}
        user.update(result)
    assert evaluate_response(user) == {"notify_tier": 1, "notify_tier_misses": 0}


def test_should_deliver_requires_generation_history():
    user = _user(last_sentence_generated_at=None, estimated_vocab=0)
    assert should_deliver(user, NOW) is False
    user["estimated_vocab"] = 120
    assert should_deliver(user, NOW) is True


def test_should_deliver_during_premium_trial():
    """トライアル中でも通常どおり配信する。"""
    assert should_deliver(_user(premium_trial_expires_at=_FUTURE), NOW) is True
    assert should_deliver(_user(premium_trial_expires_at=_PAST), NOW) is True
    assert should_deliver(
        _user(tier="premium", premium_trial_expires_at=_FUTURE), NOW
    ) is True


# --- 配信を premium 品質で出すかの判定 ---------------------------------------


def test_uses_premium_trial_follows_expiry():
    assert uses_premium_trial(_user(premium_trial_expires_at=_FUTURE), NOW) is True
    assert uses_premium_trial(_user(premium_trial_expires_at=_PAST), NOW) is False
    # 期限を持たない旧doc は free 扱い
    assert uses_premium_trial(_user(), NOW) is False
    # premium は tier 側で premium 品質になる
    assert uses_premium_trial(
        _user(tier="premium", premium_trial_expires_at=_FUTURE), NOW
    ) is False


def test_uses_premium_trial_ignores_notification_response():
    """期間制なので、通知が無視され続けても品質は落とさない。"""
    ignored = _user(
        premium_trial_expires_at=_FUTURE,
        notify_tier_misses=2,
        last_notified_at=NOW - timedelta(days=1),
        last_sentence_generated_at=NOW - timedelta(days=10),
    )
    assert uses_premium_trial(ignored, NOW) is True


def test_uses_premium_trial_naive_expiry_is_utc():
    """Firestore から naive で返っても UTC として扱う。"""
    assert uses_premium_trial(
        _user(premium_trial_expires_at=_FUTURE.replace(tzinfo=None)), NOW
    ) is True


def test_should_deliver_opt_out_and_quota():
    assert should_deliver(_user(daily_reminder_enabled=False), NOW) is False
    assert should_deliver(_user(remaining_sentences=0), NOW) is False
    assert should_deliver(_user(daily_sentence_generated=True), NOW) is False
    assert should_deliver(_user(fcm_token=None), NOW) is False


def test_should_deliver_matches_preferred_hour():
    assert should_deliver(_user(preferred_generation_hour=9), NOW) is False
    assert should_deliver(_user(preferred_generation_hour=10), NOW) is True
    # デフォルトは10時
    assert should_deliver(_user(), NOW) is True


# --- 配信コミット（トランザクション本体） -----------------------------------


class _FakeSnapshot:
    def __init__(self, data: dict | None):
        self._data = data
        self.exists = data is not None

    def to_dict(self):
        return self._data


class _FakeRef:
    def __init__(self, data: dict | None = None):
        self._data = data
        self.updates: list[dict] = []
        self.deleted = False

    def get(self, transaction=None):
        return _FakeSnapshot(self._data)

    def update(self, data: dict):
        self.updates.append(data)

    def delete(self):
        self.deleted = True


class _FakeTransaction:
    def __init__(self):
        self.sets: list[tuple] = []
        self.updates: list[tuple] = []

    def set(self, ref, data):
        self.sets.append((ref, data))

    def update(self, ref, data):
        self.updates.append((ref, data))


def _commit(user_data: dict | None):
    transaction = _FakeTransaction()
    user_ref = _FakeRef(user_data)
    sentence_ref = _FakeRef()
    result = _commit_daily_sentence_body(
        transaction, user_ref, sentence_ref, {"thai_text": "x"}, NOW
    )
    return result, transaction, user_ref


def test_commit_writes_and_returns_token():
    (token, restore), transaction, user_ref = _commit(
        _user(notify_tier=1, notify_tier_misses=2)
    )

    assert token == "token"
    assert len(transaction.sets) == 1
    _ref, update = transaction.updates[0]
    assert update["daily_sentence_generated"] is True
    # 通知失敗時に戻すのは配信前の段階
    assert restore["notify_tier"] == 1
    assert restore["notify_tier_misses"] == 2


def test_commit_rejects_when_no_longer_due():
    """外側の列挙が古くても、commit 段階で二重配信を弾く。"""
    with pytest.raises(_DeliveryNotDue):
        _commit(_user(daily_sentence_generated=True))


def test_commit_stopped_defers_update_outside_transaction():
    """停止の記録はトランザクション外へ返す（内部で書くと rollback で消える）。"""
    stopped_user = _user(
        notify_tier=TIER_STOPPED - 1,
        notify_tier_misses=TIER_MAX_MISSES - 1,
        last_notified_at=NOW - timedelta(days=60),
        last_sentence_generated_at=NOW - timedelta(days=90),
    )
    with pytest.raises(_DeliveryStopped) as exc:
        _commit(stopped_user)

    assert exc.value.updates["notify_tier"] == TIER_STOPPED
    assert "last_notified_at" in exc.value.updates


def test_commit_stopped_writes_nothing_in_transaction():
    stopped_user = _user(
        notify_tier=TIER_STOPPED - 1,
        notify_tier_misses=TIER_MAX_MISSES - 1,
        last_notified_at=NOW - timedelta(days=60),
        last_sentence_generated_at=NOW - timedelta(days=90),
    )
    transaction = _FakeTransaction()
    with pytest.raises(_DeliveryStopped):
        _commit_daily_sentence_body(
            transaction, _FakeRef(stopped_user), _FakeRef(), {}, NOW
        )

    assert transaction.sets == []
    assert transaction.updates == []


def test_notification_text_includes_key_word_and_all_lines():
    title, body = build_notification_text(
        {
            "thai_text": "เขาไม่กินเผ็ดครับ",
            "pronunciation": "カオ マイ キン ペット クラップ",
            "japanese_translation": "彼は辛いものが食べられません。",
            "key_word": "เผ็ด",
            "key_word_meaning": "辛い",
        }
    )
    assert title == "🇹🇭 今日のタイ語 · เผ็ด（辛い）"
    assert body.split("\n") == [
        "เขาไม่กินเผ็ดครับ",
        "（カオ マイ キン ペット クラップ）",
        "→ 彼は辛いものが食べられません。",
    ]


def test_notification_text_omits_missing_pronunciation_and_key_word():
    title, body = build_notification_text(
        {
            "thai_text": "สวัสดีครับ",
            "pronunciation": "",
            "japanese_translation": "こんにちは。",
        }
    )
    assert title == "🇹🇭 今日のタイ語"
    assert body == "สวัสดีครับ\n→ こんにちは。"


# --- 配信1件の流れ（トライアル消費の受け渡し） -------------------------------


class _FakeUserRef(_FakeRef):
    def __init__(self, data: dict):
        super().__init__(data)
        self.sentence_ref = _FakeRef()
        self.sentence_ref.id = "sentence-id"

    def collection(self, _name):
        return self

    def document(self):
        return self.sentence_ref


class _FakeDb:
    def __init__(self, user_ref):
        self._user_ref = user_ref

    def collection(self, _name):
        return self

    def document(self, _uid):
        return self._user_ref

    def transaction(self):
        return _FakeTransaction()


# --- スキップ理由（配信バッチのログ内訳） -------------------------------------


def test_skip_reason_none_when_deliverable():
    assert delivery_skip_reason(_user(), NOW) is None


def test_skip_reason_identifies_each_condition():
    cases = {
        "no_history": _user(last_sentence_generated_at=None, estimated_vocab=0),
        "opt_out": _user(daily_reminder_enabled=False),
        "no_token": _user(fcm_token=None),
        "already_generated": _user(daily_sentence_generated=True),
        "quota_exhausted": _user(remaining_sentences=0),
        "backoff_stopped": _user(notify_tier=TIER_STOPPED),
        "hour_mismatch": _user(preferred_generation_hour=9),
        "not_due": _user(
            notify_tier=2, last_notified_at=NOW - timedelta(days=1)
        ),
    }
    for expected, user in cases.items():
        assert delivery_skip_reason(user, NOW) == expected, expected


def test_skip_reason_priority_matches_should_deliver():
    """理由の有無は should_deliver と常に一致する（判定の二重実装を防ぐ）。"""
    for user in [
        _user(),
        _user(fcm_token=None),
        _user(remaining_sentences=0),
        _user(preferred_generation_hour=9),
        _user(notify_tier=TIER_STOPPED),
    ]:
        assert (delivery_skip_reason(user, NOW) is None) == should_deliver(user, NOW)


def test_deliver_returns_reason_when_no_sentence(monkeypatch):
    """例文が用意できなければ理由を返す（Noneは配信成功のみ）。"""
    user_ref = _FakeUserRef(_user())
    monkeypatch.setattr(
        daily_sentence_handlers, "_build_sentence", lambda db, uid, data: None
    )
    assert (
        _deliver_one(_FakeDb(user_ref), "uid", _user(), NOW) == "no_sentence"
    )
