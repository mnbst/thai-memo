from datetime import datetime, timedelta, timezone

import pytest

from daily_sentence import (
    TIER_MAX_MISSES,
    TIER_STOPPED,
    evaluate_response,
    is_due,
    local_date,
    local_hour,
    notify_utc_hour,
    should_deliver,
)
from daily_sentence_handlers import (
    _commit_daily_sentence_body,
    _DeliveryNotDue,
    _DeliveryStopped,
    build_notification_text,
)

NOW = datetime(2026, 7, 21, 1, 0, tzinfo=timezone.utc)  # JST 10:00


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


def test_open_only_holds_tier():
    user = _user(
        notify_tier=1,
        notify_tier_misses=2,
        last_notified_at=NOW - timedelta(days=3),
        last_opened_at=NOW - timedelta(days=2),
    )
    assert evaluate_response(user) == {"notify_tier": 1, "notify_tier_misses": 2}


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


def test_should_deliver_skips_during_premium_trial():
    assert should_deliver(_user(premium_trial_remaining=3), NOW) is False
    assert should_deliver(_user(premium_trial_remaining=0), NOW) is True
    # premium はトライアル残があっても配信する（そもそも消費しない）
    assert should_deliver(
        _user(tier='premium', premium_trial_remaining=3), NOW
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
