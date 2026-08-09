/**
 * quota.ts — 生成回数のクォータ定数
 *
 * remaining_sentences / remaining_quizzes の初期値・リセット値を定義。
 * dailyBatch, verifySubscription, handlePlayNotification, handleAppStoreNotification で使用。
 */

/** free ユーザーの日次リセット値（JST 0:00） */
export const FREE_DAILY_SENTENCES = 5;
export const FREE_DAILY_QUIZZES = 5;

/**
 * premium ユーザーの日次リセット値（JST 0:00）
 *
 * 例文は 2026-08-09 に 5 → 10 へ引き上げ。直近30日の実測でアクティブ人日の
 * 48.9% が上限に到達し、課金者2人が両方とも常時上限に当たっていたため
 * （premium が回数軸で free と差が無い状態だった）。
 * クイズは上限に到達するユーザーが観測されないため 5 のまま。
 */
export const PREMIUM_DAILY_SENTENCES = 10;
export const PREMIUM_DAILY_QUIZZES = 5;

/**
 * 新規ユーザーへのプレミアム体験トライアル期間（日）。
 * 2日にして「連続して使う」体験を作る。期限は premium_trial_expires_at。
 */
export const PREMIUM_TRIAL_DAYS = 2;

/**
 * 同トライアルの残回数（互換用）。
 * 残回数しか見ない旧クライアントが期間中に使い切らないよう、1日の上限×日数を入れる。
 * トライアルは premium 体験なので premium 側の上限を基準にする（free 基準だと
 * 期間中に足りなくなる）。期限切れの検知とゼロ書き込みは
 * generateThaiSentence（Python）側で行う。
 */
export const PREMIUM_TRIAL_SENTENCES = PREMIUM_DAILY_SENTENCES * PREMIUM_TRIAL_DAYS;
