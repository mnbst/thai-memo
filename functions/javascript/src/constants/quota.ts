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
 * 期間中は機能・回数とも課金 premium と完全に同じ（utils/premium.ts）。
 */
export const PREMIUM_TRIAL_DAYS = 2;

/**
 * premium_trial_remaining の付与値（凍結した互換値）。
 *
 * トライアルは期間制に一本化済みで、サーバはこの値を読まないし減らさない。
 * ただし 1.3.14（現行ストア版）までのクライアントは「残回数 <= 1 なら体験最終回」と見なして
 * 設定テーマを「おまかせ」へ戻すため、書かないと体験中の1回目でテーマが消える。
 * 該当バージョンが行き渡らなくなったらフィールドごと削除してよい。
 */
export const PREMIUM_TRIAL_SENTENCES = PREMIUM_DAILY_SENTENCES * PREMIUM_TRIAL_DAYS;
