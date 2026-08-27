package function

import (
	"context"
	"errors"
	"log"
	"os"
	"slices"
	"strings"

	"github.com/mnbst/thai-memo/functions/go/internal/callable"
	"github.com/mnbst/thai-memo/functions/go/internal/fbapp"
	"github.com/mnbst/thai-memo/functions/go/internal/tier"
)

// setUserTier は functions/javascript/src/setUserTier.ts の移植。
//
// 管理者が任意ユーザーの tier を切り替える。呼べるのは custom claim
// `admin: true` を持つユーザー、または環境変数 ADMIN_UIDS に含まれる uid のみ。
// tier はクライアントから直接書けない（firestore.rules で禁止）ため、
// 切り替えは必ずこの関数を通す。
func setUserTier(ctx context.Context, req *callable.Request) (any, error) {
	actor, err := assertAdmin(req)
	if err != nil {
		return nil, err
	}

	var in struct {
		UID          string `json:"uid"`
		Email        string `json:"email"`
		Tier         string `json:"tier"`
		DurationDays *any   `json:"duration_days"`
		Reason       string `json:"reason"`
		Force        bool   `json:"force"`
	}
	if err := req.Bind(&in); err != nil {
		return nil, err
	}

	if in.Tier != string(tier.Free) && in.Tier != string(tier.Premium) {
		return nil, callable.Errorf(callable.InvalidArgument,
			"tier は free または premium を指定してください")
	}
	if in.UID == "" && in.Email == "" {
		return nil, callable.Errorf(callable.InvalidArgument, "uid または email が必要です")
	}

	// JS 側は「未指定なら既定値、指定されたら数値かつ 0〜3650」。
	durationDays := tier.DefaultGrantDays
	if in.DurationDays != nil {
		n, ok := (*in.DurationDays).(float64)
		if !ok || n < 0 || n > 3650 {
			return nil, callable.Errorf(callable.InvalidArgument,
				"duration_days は 0〜3650 の数値で指定してください")
		}
		durationDays = int(n)
	}

	uid := in.UID
	if uid == "" {
		// email 指定はサポート対応用（問い合わせはメールアドレスで来る）
		authCli, err := fbapp.Auth(ctx)
		if err != nil {
			return nil, err
		}
		user, err := authCli.GetUserByEmail(ctx, in.Email)
		if err != nil {
			return nil, callable.Errorf(callable.NotFound,
				"該当ユーザーが見つかりません: %s", in.Email)
		}
		uid = user.UID
	}

	db, err := fbapp.Firestore(ctx)
	if err != nil {
		return nil, err
	}

	result, err := tier.ApplyTier(ctx, db, tier.Params{
		UID:          uid,
		Tier:         tier.Tier(in.Tier),
		DurationDays: durationDays,
		Source:       "admin",
		Actor:        actor,
		Reason:       in.Reason,
		Force:        in.Force,
	})
	if err != nil {
		var te *tier.Error
		if errors.As(err, &te) {
			code := callable.NotFound
			if te.Code == tier.FailedPrecondition {
				code = callable.FailedPrecondition
			}
			return nil, &callable.Error{Code: code, Message: te.Message}
		}
		log.Printf("setUserTier failed: %v", err)
		return nil, callable.Errorf(callable.Internal, "tier の更新に失敗しました")
	}

	// expires_at は無期限のとき JS では null になる。
	var expiresAt any
	if result.ExpiresAt != "" {
		expiresAt = result.ExpiresAt
	}
	return map[string]any{
		"uid":           result.UID,
		"tier":          string(result.Tier),
		"previous_tier": string(result.PreviousTier),
		"expires_at":    expiresAt,
	}, nil
}

// assertAdmin は setUserTier.ts:assertAdmin。
func assertAdmin(req *callable.Request) (string, error) {
	uid, err := req.RequireAuth()
	if err != nil {
		return "", err
	}
	if req.Auth.HasClaim("admin") || slices.Contains(adminUIDs(), uid) {
		return uid, nil
	}
	log.Printf("setUserTier: 権限のない呼び出し uid=%s", uid)
	return "", callable.Errorf(callable.PermissionDenied, "管理者権限が必要です")
}

// adminUIDs は環境変数 ADMIN_UIDS（カンマ区切り）の許可リスト。
func adminUIDs() []string {
	var out []string
	for _, s := range strings.Split(os.Getenv("ADMIN_UIDS"), ",") {
		if s = strings.TrimSpace(s); s != "" {
			out = append(out, s)
		}
	}
	return out
}
