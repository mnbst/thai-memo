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

/** 課金 premium もしくはトライアル中か */
export function isEffectivePremium(
  userData: UserData,
  now = Date.now(),
): boolean {
  return userData?.tier === 'premium' || isTrialActive(userData, now);
}
