"""毎日例文の配信ロジック（純粋関数部分）。

Cloud Functions のエントリポイントは daily_sentence_handlers.py にある。
テスト容易性のため、判定ロジックはここに副作用なしで置く。
"""

from datetime import datetime, timedelta, timezone
from zoneinfo import ZoneInfo

# 段階ごとの配信間隔（日）。notify_tier == len(...) で配信停止。
TIER_INTERVAL_DAYS = [1, 3, 10, 30]
TIER_STOPPED = len(TIER_INTERVAL_DAYS)
# 同じ段階で無反応がこの回数たまると次の段階へ落とす
TIER_MAX_MISSES = 3

DEFAULT_TIMEZONE = "Asia/Tokyo"
DEFAULT_GENERATION_HOUR = 10

# キャッシュヒットするまでターゲット語を引き直す回数
MAX_TARGET_WORD_RETRY = 5


def _local(tz_name: str | None, now: datetime) -> datetime:
    """不正・未設定のtz名は Asia/Tokyo にフォールバックしてローカル時刻へ変換する。"""
    try:
        tz = ZoneInfo(tz_name or DEFAULT_TIMEZONE)
    except Exception:
        tz = ZoneInfo(DEFAULT_TIMEZONE)
    return now.astimezone(tz)


def local_hour(tz_name: str | None, now: datetime) -> int:
    return _local(tz_name, now).hour


def local_date(tz_name: str | None, now: datetime) -> str:
    return _local(tz_name, now).strftime("%Y-%m-%d")


def _as_datetime(value) -> datetime | None:
    """Firestore の timestamp を tz-aware datetime に正規化する。"""
    if value is None:
        return None
    if isinstance(value, datetime):
        return value if value.tzinfo else value.replace(tzinfo=timezone.utc)
    return None


def has_generation_history(user_data: dict) -> bool:
    """一度でも例文を生成したことがあるか。

    last_sentence_generated_at が導入される前に生成したきりのユーザーを
    estimated_vocab で救う。
    """
    if user_data.get("last_sentence_generated_at") is not None:
        return True
    return user_data.get("estimated_vocab", 0) > 0


def is_due(user_data: dict, now: datetime) -> bool:
    """段階ごとの配信間隔を満たしているか。初回（未通知）は常に True。"""
    tier = user_data.get("notify_tier", 0)
    if tier >= TIER_STOPPED:
        return False
    last_notified = _as_datetime(user_data.get("last_notified_at"))
    if last_notified is None:
        return True
    return now >= last_notified + timedelta(days=TIER_INTERVAL_DAYS[tier])


def evaluate_response(user_data: dict) -> dict:
    """前回通知への反応を評価し、更新後の段階を返す。

    「次へ」押下（last_sentence_generated_at）を主シグナル、開封（last_opened_at）を
    副シグナルとする。どちらも動いていない場合だけ段階が進む。
    """
    tier = user_data.get("notify_tier", 0)
    misses = user_data.get("notify_tier_misses", 0)
    last_notified = _as_datetime(user_data.get("last_notified_at"))

    if last_notified is None:
        return {"notify_tier": tier, "notify_tier_misses": misses}

    generated_at = _as_datetime(user_data.get("last_sentence_generated_at"))
    if generated_at is not None and generated_at > last_notified:
        return {"notify_tier": 0, "notify_tier_misses": 0}

    opened_at = _as_datetime(user_data.get("last_opened_at"))
    if opened_at is not None and opened_at > last_notified:
        return {"notify_tier": tier, "notify_tier_misses": misses}

    misses += 1
    if misses >= TIER_MAX_MISSES:
        tier += 1
        misses = 0
    return {"notify_tier": tier, "notify_tier_misses": misses}


def should_deliver(user_data: dict, now: datetime) -> bool:
    """配信対象かどうか。反応評価の前に効く足切り条件をまとめて判定する。"""
    if not has_generation_history(user_data):
        return False
    if user_data.get("daily_reminder_enabled") is False:
        return False
    if not user_data.get("fcm_token"):
        return False
    if user_data.get("daily_sentence_generated"):
        return False
    if user_data.get("remaining_sentences", 0) <= 0:
        return False
    if user_data.get("notify_tier", 0) >= TIER_STOPPED:
        return False
    # プレミアム体験トライアル中は配信しない。free の配信はキャッシュ品質なので、
    # premium品質を体験してもらう期間に混ぜると差が伝わらなくなる。
    # またクォータを1消費するぶんトライアルの消化も遅れる。
    if (
        user_data.get("tier") != "premium"
        and user_data.get("premium_trial_remaining", 0) > 0
    ):
        return False

    hour = local_hour(user_data.get("timezone"), now)
    if hour != user_data.get("preferred_generation_hour", DEFAULT_GENERATION_HOUR):
        return False

    return is_due(user_data, now)
