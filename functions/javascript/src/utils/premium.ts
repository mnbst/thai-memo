/**
 * premium.ts — 「実効プレミアム」の判定
 *
 * 課金中の premium と、新規ユーザーのプレミアム体験トライアル中を同じものとして
 * 扱うための唯一の判定。トライアル中は完全に premium と同じ機能・同じ回数を出す
 * 方針なので、tier だけを見る分岐を各所に書かない。
 *
 * トライアルは期間制（premium_trial_expires_at）。
 */

type UserData = Record<string, unknown>;

const DAY_MS = 24 * 60 * 60 * 1000;
const JST_OFFSET_MS = 9 * 60 * 60 * 1000;
const GRACE_PERIOD_MAX_MS = 30 * DAY_MS;

/**
 * 与えた時刻以降で最初の JST 0:00 に切り上げる（ちょうど 0:00 ならそのまま）。
 *
 * トライアルの期限をクォータのリセット境界（dailyBatch, JST 0:00）に揃えるため。
 * 揃えないと「期限は切れたが、その日のぶんの premium の回数はまだ残っている」
 * 半端な時間帯ができ、体験終了の案内と実際に使える回数がずれる。
 */
export function ceilToJstMidnight(ms: number): number {
  return Math.ceil((ms + JST_OFFSET_MS) / DAY_MS) * DAY_MS - JST_OFFSET_MS;
}

/** 登録時刻から数えたトライアル期限（JST 0:00 に切り上げ済み） */
export function trialExpiresAtMsFrom(nowMs: number, days: number): number {
  return ceilToJstMidnight(nowMs + days * DAY_MS);
}

export function trialExpiresAtMs(userData: UserData): number | null {
  const value = userData?.premium_trial_expires_at as
    | { toMillis?: () => number }
    | undefined;
  const ms = value?.toMillis?.();
  return typeof ms === 'number' ? ms : null;
}

/** プレミアム体験トライアルが有効か */
export function isTrialActive(userData: UserData, now = Date.now()): boolean {
  const expiresAt = trialExpiresAtMs(userData);
  return expiresAt !== null && now < expiresAt;
}

/** トライアルを持っていて、既に期限が切れているか */
export function isTrialExpired(userData: UserData, now = Date.now()): boolean {
  const expiresAt = trialExpiresAtMs(userData);
  return expiresAt !== null && now >= expiresAt;
}

/** 課金 premium もしくはトライアル中か。tier反映待ちは購読期限から補完する。 */
export function isEffectivePremium(
  userData: UserData,
  now = Date.now(),
): boolean {
  if (userData?.tier === 'premium' || isTrialActive(userData, now)) return true;

  const subscription = userData?.subscription as
    | Record<string, unknown>
    | undefined;
  const status = subscription?.status;
  // REFUND / REVOKE 後も lifetime や将来の expires_at が残ることがある。
  // 取消済みの権利を subscription の補完判定で復活させない。
  if (status === 'expired' || status === 'revoked' || status === 'refunded') {
    return false;
  }
  if (subscription?.lifetime === true && status === 'active') return true;
  if (status !== 'active' && status !== 'canceled' && status !== 'grace_period') {
    return false;
  }

  const expiresAt = subscription?.expires_at as
    | { toMillis?: () => number }
    | undefined;
  const expiresAtMs = expiresAt?.toMillis?.();
  if (typeof expiresAtMs !== 'number') return false;
  if (now < expiresAtMs) return true;
  return status === 'grace_period'
    && now - expiresAtMs <= GRACE_PERIOD_MAX_MS;
}
