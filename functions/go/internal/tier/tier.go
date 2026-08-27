// Package tier は tier 手動付与の中核ロジック。
// functions/javascript/src/services/tierService.ts の移植。
//
// ストア購入由来の subscription は上書きしない（force 指定時のみ許可）。
// premium 付与は expires_at を必ず持たせ、subscriptionStatus / dailyBatch の
// 既存の期限切れ処理でそのまま free に戻るようにする（無期限は days=0 のみ）。
package tier

import (
	"context"
	"fmt"
	"log"
	"time"

	"cloud.google.com/go/firestore"

	"github.com/mnbst/thai-memo/functions/go/internal/quota"
)

// ManualPlatform は手動付与の subscription.platform 値（ストア購入と区別する）。
const ManualPlatform = "manual"

// DefaultGrantDays は premium 付与時のデフォルト期間。
const DefaultGrantDays = 30

// Tier は free か premium。
type Tier string

const (
	Free    Tier = "free"
	Premium Tier = "premium"
)

// Params は ApplyTier の引数（tierService.ts:ApplyTierParams）。
type Params struct {
	UID  string
	Tier Tier
	// DurationDays は premium 付与期間（日）。0 で無期限。free 指定時は無視。
	DurationDays int
	// Source は付与の出所。'admin' / 'coupon:<code>' など。
	Source string
	// Actor は実行者の uid（監査ログ用）。バッチ等で不在なら空文字。
	Actor string
	// Reason は監査ログに残す任意メモ。
	Reason string
	// Force はストア購入由来の subscription を上書きしてよいか。
	Force bool
}

// Result は ApplyTier の返り値。ExpiresAt は ISO8601（無期限なら空文字）。
type Result struct {
	UID          string
	Tier         Tier
	PreviousTier Tier
	ExpiresAt    string
}

// Code は TierError の種別。callable のエラーコードにそのまま写す。
type Code string

const (
	NotFound           Code = "not-found"
	FailedPrecondition Code = "failed-precondition"
)

// Error は tierService.ts:TierError。
type Error struct {
	Code    Code
	Message string
}

func (e *Error) Error() string { return e.Message }

// isoMillis は JS の Date#toISOString と同じ書式（ミリ秒3桁 + Z）。
const isoMillis = "2006-01-02T15:04:05.000Z"

// ApplyTier はユーザーの tier を書き換え、監査ログを tier_grants に残す。
// tier が変わった場合のみクォータをリセットする（既存 CF と同じ方針）。
func ApplyTier(ctx context.Context, db *firestore.Client, p Params) (*Result, error) {
	userRef := db.Collection("users").Doc(p.UID)
	snap, err := userRef.Get(ctx)
	if err != nil || !snap.Exists() {
		return nil, &Error{NotFound, fmt.Sprintf("ユーザーが存在しません: %s", p.UID)}
	}
	data := snap.Data()

	previous := Free
	if s, _ := data["tier"].(string); s == string(Premium) {
		previous = Premium
	}

	subscription, _ := data["subscription"].(map[string]any)
	platform, _ := subscription["platform"].(string)
	status, _ := subscription["status"].(string)
	isStore := platform == "ios" || platform == "android"
	isStoreActive := isStore && (status == "active" || status == "grace_period")

	if isStoreActive && !p.Force {
		return nil, &Error{FailedPrecondition, fmt.Sprintf(
			"ストア購入が有効なユーザーです（platform=%s, status=%s）。"+
				"上書きするには force=true を指定してください", platform, status)}
	}

	update := map[string]any{"tier": string(p.Tier)}

	if previous != p.Tier {
		if p.Tier == Premium {
			update["remaining_sentences"] = quota.PremiumDailySentences
			update["remaining_quizzes"] = quota.PremiumDailyQuizzes
		} else {
			update["remaining_sentences"] = quota.FreeDailySentences
			update["remaining_quizzes"] = quota.FreeDailyQuizzes
		}
	}

	// expires_at は premium かつ期間指定ありのときだけ持たせる。
	var expiresAt any // time.Time または nil
	var expiresISO string
	if p.Tier == Premium && p.DurationDays > 0 {
		t := time.Now().Add(time.Duration(p.DurationDays) * 24 * time.Hour)
		// JS は Timestamp.fromMillis なのでミリ秒までしか持たない。揃える。
		t = time.UnixMilli(t.UnixMilli())
		expiresAt = t
		expiresISO = t.UTC().Format(isoMillis)
	}

	// ストア購入の subscription は触らない（force 時のみ手動値で上書き）。
	// MergeAll はネストしたマップもフィールド単位でマージするため、
	// purchase_token / original_transaction_id は保持される。
	if !isStore || p.Force {
		subStatus := "expired"
		if p.Tier == Premium {
			subStatus = "active"
		}
		update["subscription"] = map[string]any{
			"platform":      ManualPlatform,
			"product_id":    nil,
			"source":        p.Source,
			"status":        subStatus,
			"expires_at":    expiresAt,
			"auto_renewing": false,
			"updated_at":    firestore.ServerTimestamp,
		}
	}

	if _, err := userRef.Set(ctx, update, firestore.MergeAll); err != nil {
		return nil, fmt.Errorf("users の更新に失敗: %w", err)
	}

	var durationDays any
	if p.Tier == Premium {
		durationDays = p.DurationDays
	}
	var actor any
	if p.Actor != "" {
		actor = p.Actor
	}
	var reason any
	if p.Reason != "" {
		reason = p.Reason
	}
	if _, _, err := db.Collection("tier_grants").Add(ctx, map[string]any{
		"uid":           p.UID,
		"tier":          string(p.Tier),
		"previous_tier": string(previous),
		"duration_days": durationDays,
		"expires_at":    expiresAt,
		"source":        p.Source,
		"actor":         actor,
		"reason":        reason,
		"forced":        p.Force,
		"created_at":    firestore.ServerTimestamp,
	}); err != nil {
		return nil, fmt.Errorf("tier_grants への記録に失敗: %w", err)
	}

	actorLog := "none"
	if p.Actor != "" {
		actorLog = p.Actor
	}
	expiresLog := "none"
	if expiresISO != "" {
		expiresLog = expiresISO
	}
	log.Printf("applyTier: uid=%s %s->%s source=%s actor=%s expires_at=%s",
		p.UID, previous, p.Tier, p.Source, actorLog, expiresLog)

	return &Result{
		UID:          p.UID,
		Tier:         p.Tier,
		PreviousTier: previous,
		ExpiresAt:    expiresISO,
	}, nil
}
