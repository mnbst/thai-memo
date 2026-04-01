/**
 * quota.ts — 生成回数のクォータ定数
 *
 * remaining_sentences / remaining_quizzes の初期値・リセット値を定義。
 * dailyBatch, verifySubscription, handlePlayNotification, handleAppStoreNotification で使用。
 */

/** 初回ユーザー（フィールド未存在時）のボーナス回数 */
export const INITIAL_SENTENCES = 3;
export const INITIAL_QUIZZES = 3;

/** free ユーザーの日次リセット値 */
export const FREE_DAILY_SENTENCES = 1;
export const FREE_DAILY_QUIZZES = 2;

/** premium ユーザーの日次リセット値 */
export const PREMIUM_DAILY_SENTENCES = 5;
export const PREMIUM_DAILY_QUIZZES = 10;
