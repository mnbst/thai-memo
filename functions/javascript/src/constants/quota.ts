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
