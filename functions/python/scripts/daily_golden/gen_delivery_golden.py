"""daily_sentence_handlers.py の配信制御を Python 実装から書き出す。

I/O 境界（Firestore・produce_sentence）だけを差し替えて本物の関数を呼ぶ。
Go 版 functions/go/deliver_daily_sentence.go との差分テストに使う。
出力: functions/python/scripts/daily_golden/delivery_golden.json
"""

import json
import os
import sys
from datetime import datetime, timedelta, timezone

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", ".."))

from firebase_admin import firestore  # noqa: E402

import daily_sentence_handlers as dsh  # noqa: E402

OUT = os.path.join(os.path.dirname(__file__), "delivery_golden.json")

NOW = datetime(2026, 8, 27, 1, 0, 0, tzinfo=timezone.utc)

SENTENCE = {
    "thai_text": "ฉันกินข้าว",
    "pronunciation": "chǎn kin khâao",
    "japanese_translation": "私はご飯を食べる",
    "word_breakdown": [{"word": "ฉัน", "meaning": "私"}],
    "context": {"topic": "食べ物"},
}


def _sentinel(value):
    """Firestore のセンチネル値を JSON に出せる記号へ落とす。"""
    if value is firestore.firestore.SERVER_TIMESTAMP:
        return "@server_timestamp"
    if value is firestore.firestore.DELETE_FIELD:
        return "@delete"
    if isinstance(value, firestore.firestore.Increment):
        return f"@increment:{value.value}"
    if isinstance(value, datetime):
        return value.isoformat()
    return value


def _dump(updates: dict) -> dict:
    return {k: _sentinel(v) for k, v in updates.items()}


# ---------------------------------------------------------------- _build_sentence


def build_sentence_cases():
    cases = []
    scenarios = [
        # (説明, user_data, premium 生成の結果)
        ("free はキャッシュのみ", {"tier": "free"}, None),
        ("free・語彙上限で頭打ち", {"tier": "free", "estimated_vocab": 5000}, None),
        ("premium は LLM 生成", {"tier": "premium", "estimated_vocab": 800}, "ok"),
        ("premium が失敗したらキャッシュへ",
         {"tier": "premium", "estimated_vocab": 800}, "raise"),
        ("premium が None ならキャッシュへ",
         {"tier": "premium", "estimated_vocab": 800}, "none"),
        ("premium・本人指定テーマ",
         {"tier": "premium", "preferred_topic": "旅行"}, "ok"),
        ("premium・ヒアリングの用途",
         {"tier": "premium", "interview": {"goal": "travel"}}, "ok"),
        ("premium・指定もヒアリングも無い", {"tier": "premium"}, "ok"),
        ("premium・指定が空文字ならヒアリングへ",
         {"tier": "premium", "preferred_topic": "",
          "interview": {"goal": "work"}}, "ok"),
        ("トライアル中の free も premium 扱い",
         {"tier": "free",
          "premium_trial_expires_at": NOW + timedelta(days=1)}, "ok"),
        ("トライアル切れは free 扱い",
         {"tier": "free",
          "premium_trial_expires_at": NOW - timedelta(days=1)}, None),
        ("en ユーザー", {"tier": "free", "app_language": "en"}, None),
        ("premium の en ユーザー",
         {"tier": "premium", "app_language": "en"}, "ok"),
        ("未知の言語は ja へ", {"tier": "free", "app_language": "th"}, None),
        ("キャッシュも無ければ配信しない",
         {"tier": "free", "no_cache": True}, None),
    ]

    for name, user_data, premium_result in scenarios:
        calls = []

        def fake_produce(db, uid, params, *, use_premium_spec, estimated_vocab,
                         cache_only=False, select_retry=1, lang="ja"):
            calls.append({
                "params": dict(params),
                "use_premium_spec": use_premium_spec,
                "estimated_vocab": estimated_vocab,
                "cache_only": cache_only,
                "select_retry": select_retry,
                "lang": lang,
            })
            if use_premium_spec:
                if premium_result == "raise":
                    raise RuntimeError("LLM down")
                if premium_result == "none":
                    return None
                return ({**SENTENCE}, ["w1"], "topic1", False)
            if user_data.get("no_cache"):
                return None
            return ({**SENTENCE}, ["w2"], "topic2", True)

        # ヒアリングからのテーマ決定は抽選を含むので固定する。
        orig = (dsh.produce_sentence, dsh.resolve_interview_topic)
        dsh.produce_sentence = fake_produce
        dsh.resolve_interview_topic = lambda ud: (
            "旅行・おでかけ" if (ud.get("interview") or {}).get("goal") else ""
        )
        try:
            got = dsh._build_sentence(None, "uid", user_data)
        finally:
            dsh.produce_sentence, dsh.resolve_interview_topic = orig

        cases.append({
            "name": name,
            "user_data": _dump(user_data),
            "premium_result": premium_result,
            "calls": calls,
            "want": None if got is None else {
                "target_words": got[1],
                "use_premium_spec": got[2],
            },
        })
    return cases


# ------------------------------------------------------- _commit_daily_sentence


class _FakeSnapshot:
    def __init__(self, data):
        self._data = data
        self.exists = data is not None

    def to_dict(self):
        return self._data


class _FakeRef:
    def __init__(self, data):
        self._data = data
        self.id = "sentence-id"

    def get(self, transaction=None):
        return _FakeSnapshot(self._data)


class _FakeTransaction:
    def __init__(self):
        self.sets = []
        self.updates = []

    def set(self, ref, data):
        self.sets.append(data)

    def update(self, ref, data):
        self.updates.append(data)


def commit_cases():
    past = NOW - timedelta(days=100)
    old = NOW - timedelta(days=40)
    base = {
        "fcm_token": "tok",
        "daily_reminder_enabled": True,
        "timezone": "Asia/Tokyo",
        "remaining_sentences": 3,
        "daily_sentence_generated": False,
        "preferred_generation_hour": 10,
        "last_sentence_generated_at": past,
    }
    scenarios = [
        ("配信する", {}),
        ("段階1・無反応で進む", {"notify_tier": 1, "notify_tier_misses": 1,
                              "last_notified_at": old}),
        ("開封済みで連続無反応をリセット",
         {"notify_tier": 2, "notify_tier_misses": 1, "last_notified_at": old,
          "last_opened_at": NOW - timedelta(days=1)}),
        ("「次へ」押下で段階ごとリセット",
         {"notify_tier": 3, "notify_tier_misses": 1, "last_notified_at": old,
          "last_sentence_generated_at": NOW - timedelta(days=1)}),
        ("配信停止に達する", {"notify_tier": 3, "notify_tier_misses": 2,
                            "last_notified_at": old}),
        ("すでに配信停止", {"notify_tier": 4, "last_notified_at": old}),
        ("間隔が足りない", {"notify_tier": 1,
                            "last_notified_at": NOW - timedelta(days=1)}),
        ("当日配信済み", {"daily_sentence_generated": True}),
        ("クォータ切れ", {"remaining_sentences": 0}),
        ("通知オフ", {"daily_reminder_enabled": False}),
        ("トークン無し", {"fcm_token": None}),
        ("生成履歴が無い", {"last_sentence_generated_at": None}),
        ("時刻が合わない", {"preferred_generation_hour": 23}),
        ("user doc が無い", None),
    ]

    cases = []
    for name, overrides in scenarios:
        if overrides is None:
            data = None
        else:
            data = {**base, **overrides}
            data = {k: v for k, v in data.items() if v is not None}
            if overrides.get("daily_reminder_enabled") is False:
                data["daily_reminder_enabled"] = False

        tx = _FakeTransaction()
        user_ref = _FakeRef(data)
        outcome, token, restore, stopped = "delivered", None, None, None
        try:
            token, restore = dsh._commit_daily_sentence_body(
                tx, user_ref, _FakeRef(None), {"thai_text": "x"}, NOW
            )
        except dsh._DeliveryNotDue:
            outcome = "not_due"
        except dsh._DeliveryStopped as exc:
            outcome = "stopped"
            stopped = _dump(exc.updates)

        cases.append({
            "name": name,
            "user_data": _dump(data) if data is not None else None,
            "outcome": outcome,
            "token": token,
            "restore": _dump(restore) if restore else None,
            "stopped_updates": stopped,
            "user_update": _dump(tx.updates[0]) if tx.updates else None,
            "wrote_sentence": len(tx.sets),
        })
    return cases


# ------------------------------------------------------------ _rollback_delivery


class _RecordingRef:
    def __init__(self):
        self.deleted = 0
        self.updates = []

    def delete(self):
        self.deleted += 1

    def update(self, data):
        self.updates.append(data)


def rollback_cases():
    restores = [
        {"notify_tier": 0, "notify_tier_misses": 0,
         "last_notified_at": firestore.firestore.DELETE_FIELD},
        {"notify_tier": 2, "notify_tier_misses": 1,
         "last_notified_at": NOW - timedelta(days=3)},
    ]
    cases = []
    for restore in restores:
        for delete_token in [True, False]:
            user_ref, sentence_ref = _RecordingRef(), _RecordingRef()
            dsh._rollback_delivery(
                user_ref, sentence_ref, restore, delete_token=delete_token
            )
            cases.append({
                "restore": _dump(restore),
                "delete_token": delete_token,
                "sentence_deleted": sentence_ref.deleted,
                "user_update": _dump(user_ref.updates[0]),
            })
    return cases


def main() -> None:
    out = {
        "now": NOW.isoformat(),
        "build_sentence": build_sentence_cases(),
        "commit": commit_cases(),
        "rollback": rollback_cases(),
    }
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False)
    print(f"wrote {OUT}")
    for k, v in out.items():
        if isinstance(v, list):
            print(f"  {k}: {len(v)}")


if __name__ == "__main__":
    main()
