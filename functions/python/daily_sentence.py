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


def notify_utc_hour(user_data: dict, now: datetime) -> int | None:
    """現地の配信希望時刻が UTC の何時の起動に当たるかを求める。

    users/{uid}.notify_utc_hour に非正規化して配信対象クエリの絞り込みに使う
    （毎時 users 全件を読むのを避けるため）。値の維持は主に dailyBatch が行うが、
    クライアントが設定を書いた直後に反映させるためロジックはここにも置く。

    オフセットの引き算ではなく24通りを実際にローカル変換して探す。+5:30 / +5:45 の
    ような分単位オフセットでも現地の各時刻はUTCのいずれか1時刻と1対1に対応する
    （配信が現地 10:30 になるズレはあるが、これは従来の挙動と同じ）。

    DST 春の切り替え日はその現地時刻自体が存在しないため None を返す。
    """
    preferred = user_data.get("preferred_generation_hour", DEFAULT_GENERATION_HOUR)
    day = now.astimezone(timezone.utc).replace(minute=0, second=0, microsecond=0)
    for hour in range(24):
        if local_hour(user_data.get("timezone"), day.replace(hour=hour)) == preferred:
            return hour
    return None


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

    開封は段階（notify_tier）までは戻さないが、無反応の連続カウントは0に戻す。
    届いた通知に反応している以上、間隔を広げる方向へ進めるべきではないため。
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
        return {"notify_tier": tier, "notify_tier_misses": 0}

    misses += 1
    if misses >= TIER_MAX_MISSES:
        tier += 1
        misses = 0
    return {"notify_tier": tier, "notify_tier_misses": misses}


def uses_premium_trial(user_data: dict, now: datetime | None = None) -> bool:
    """この配信をプレミアム体験トライアル枠（premium品質）で出すか。

    トライアルは期間制なので、期間中の free ユーザーは配信も premium 品質にする。
    判定は generateThaiSentence 側（sentence_handlers._resolve_trial_active）と同じ
    期限のみで、消費という概念は無い。
    """
    if user_data.get("tier") == "premium":
        return False
    expires_at = user_data.get("premium_trial_expires_at")
    if not isinstance(expires_at, datetime):
        return False
    if expires_at.tzinfo is None:
        expires_at = expires_at.replace(tzinfo=timezone.utc)
    return (now or datetime.now(timezone.utc)) < expires_at


def delivery_skip_reason(user_data: dict, now: datetime) -> str | None:
    """配信を見送る理由。配信対象なら None。

    理由を文字列で返すのは、配信バッチのログに内訳を残すため。
    「通知が届いていない」を調べるたびに Firestore を読んで条件を手で再現するのは
    非効率なので、判断に使う値は常設ログにしておく。
    """
    if not has_generation_history(user_data):
        return "no_history"
    if user_data.get("daily_reminder_enabled") is False:
        return "opt_out"
    if not user_data.get("fcm_token"):
        return "no_token"
    if user_data.get("daily_sentence_generated"):
        return "already_generated"
    if user_data.get("remaining_sentences", 0) <= 0:
        return "quota_exhausted"
    if user_data.get("notify_tier", 0) >= TIER_STOPPED:
        return "backoff_stopped"

    hour = local_hour(user_data.get("timezone"), now)
    if hour != user_data.get("preferred_generation_hour", DEFAULT_GENERATION_HOUR):
        # notify_utc_hour で絞ってから呼ぶので、これが出るのは非正規化値が古いとき。
        return "hour_mismatch"

    if not is_due(user_data, now):
        return "not_due"
    return None


def should_deliver(user_data: dict, now: datetime) -> bool:
    """配信対象かどうか。反応評価の前に効く足切り条件をまとめて判定する。"""
    return delivery_skip_reason(user_data, now) is None
