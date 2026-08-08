/**
 * quota.ts — 生成回数のクォータ定数
 *
 * remaining_sentences / remaining_quizzes の初期値・リセット値を定義。
 * dailyBatch, verifySubscription, handlePlayNotification, handleAppStoreNotification で使用。
 */

/** free ユーザーの日次リセット値（JST 0:00） */
export const FREE_DAILY_SENTENCES = 5;
export const FREE_DAILY_QUIZZES = 5;

/** premium ユーザーの日次リセット値（JST 0:00） */
export const PREMIUM_DAILY_SENTENCES = 5;
export const PREMIUM_DAILY_QUIZZES = 5;

/**
 * 新規ユーザーへのプレミアム体験トライアル期間（日）。
 * 2日にして「連続して使う」体験を作る。期限は premium_trial_expires_at。
 */
export const PREMIUM_TRIAL_DAYS = 2;

/**
 * 同トライアルの残回数（互換用）。
 * 残回数しか見ない旧クライアントが期間中に使い切らないよう、1日の上限×日数を入れる。
 * 期限切れの検知とゼロ書き込みは generateThaiSentence（Python）側で行う。
 */
export const PREMIUM_TRIAL_SENTENCES = FREE_DAILY_SENTENCES * PREMIUM_TRIAL_DAYS;
