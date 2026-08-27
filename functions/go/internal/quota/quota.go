// Package quota は生成回数のクォータ定数。
// functions/javascript/src/constants/quota.ts の移植。**両者を必ず一致させること。**
package quota

const (
	// FreeDailySentences は free ユーザーの日次リセット値（JST 0:00）。
	FreeDailySentences = 5

	// FreeDailyQuizzes はクイズの日次リセット値。
	// クイズの日次上限は 2026-08-25 に撤廃済みで、この値は既存ドキュメントの
	// 形を保つためだけに書き続けている（読み手は居ない）。
	FreeDailyQuizzes = 5

	// PremiumDailySentences は premium ユーザーの日次リセット値。
	PremiumDailySentences = 20

	// PremiumDailyQuizzes は上限としては機能しない。FreeDailyQuizzes 参照。
	PremiumDailyQuizzes = 5

	// PremiumTrialDays は新規ユーザーへのプレミアム体験トライアル期間（日）。
	PremiumTrialDays = 2

	// PremiumTrialSentences は premium_trial_remaining の付与値（凍結した互換値）。
	// サーバは読まないが、1.3.14 までのクライアントがテーマ判定に使う。
	PremiumTrialSentences = PremiumDailySentences * PremiumTrialDays
)
