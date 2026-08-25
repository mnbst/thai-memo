/**
 * quota.ts — 生成回数のクォータ定数
 *
 * remaining_sentences / remaining_quizzes の初期値・リセット値を定義。
 * dailyBatch, verifySubscription, handlePlayNotification, handleAppStoreNotification で使用。
 */

/** free ユーザーの日次リセット値（JST 0:00） */
export const FREE_DAILY_SENTENCES = 5;

/**
 * クイズの日次上限は 2026-08-25 に撤廃した（generateQuiz は remaining_quizzes を
 * 読まないし減らさない）。出題対象は SRS で期日を迎えた自分の例文だけなので、
 * 実質的な上限は例文側のクォータが決めている。
 * remaining_quizzes フィールド自体は既存ドキュメントの形を保つために書き続けており、
 * 以下の値はそのリセット用。読み手が居なくなったらフィールドごと削除してよい。
 */
export const FREE_DAILY_QUIZZES = 5;

/**
 * premium ユーザーの日次リセット値（JST 0:00）
 *
 * 例文は 2026-08-09 に 5 → 10、2026-08-25 に 10 → 20 へ引き上げ。後者は
 * 「1日1文」から「たくさん触れる」へブランドを寄せる方針に合わせたもので、
 * free 5 に対して 4 倍の差を作る。月額600円・Apple手取り510円に対し、
 * 20文/日をフル消化しても AI コストは月約275円（例文 $0.00246/回 実測）で粗利は残る。
 * クイズは上限そのものを撤廃した（FREE_DAILY_QUIZZES のコメント参照）。
 */
export const PREMIUM_DAILY_SENTENCES = 20;
/** 上限としては機能しない。FREE_DAILY_QUIZZES のコメント参照。 */
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
