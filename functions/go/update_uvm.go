package function

import (
	"context"
	"encoding/json"
	"log"

	"cloud.google.com/go/firestore"

	"github.com/mnbst/thai-memo/functions/go/internal/callable"
	"github.com/mnbst/thai-memo/functions/go/internal/fbapp"
	"github.com/mnbst/thai-memo/functions/go/internal/uvm"
)

// updateUvmRequest は callable の data。
type updateUvmRequest struct {
	// Results は [{"word","is_correct","hint_level","sentence_reviewed"}, ...]。
	// hint_level は数値でないこともあるので生のまま受けて後で解釈する。
	Results  []map[string]any `json:"results"`
	QuizType string           `json:"quiz_type"`
}

// updateUvm は functions/python/uvm_handlers.py:updateUvm の移植。
// クイズ結果から UVM を更新する。
func updateUvm(ctx context.Context, req *callable.Request) (any, error) {
	uid, err := req.RequireAuth()
	if err != nil {
		return nil, err
	}

	var in updateUvmRequest
	if err := req.Bind(&in); err != nil {
		return nil, err
	}
	if len(in.Results) == 0 {
		return map[string]any{"success": true, "updated": 0}, nil
	}

	results := make([]uvm.Result, 0, len(in.Results))
	for _, raw := range in.Results {
		r, err := parseResult(raw)
		if err != nil {
			return nil, err
		}
		results = append(results, r)
	}

	db, err := fbapp.Firestore(ctx)
	if err != nil {
		return nil, err
	}

	freqRank, err := uvm.GetFreqRank(ctx, fbapp.ProjectID())
	if err != nil {
		return nil, callable.Errorf(callable.Internal, "語彙データを読み込めませんでした")
	}

	// tier はクライアントから書けないサーバー専用フィールド。
	isPremium := false
	if snap, err := db.Collection("users").Doc(uid).Get(ctx); err == nil && snap.Exists() {
		tier, _ := snap.Data()["tier"].(string)
		isPremium = tier == "premium"
	}

	log.Printf("updateUvm: uid=%s, quiz_type=%s, results=%d", uid, in.QuizType, len(results))

	if err := uvm.BatchUpdate(ctx, db, uid, results, freqRank, in.QuizType, isPremium); err != nil {
		log.Printf("updateUvm: uid=%s error=%v", uid, err)
		return nil, callable.Errorf(callable.Internal, "学習データの更新に失敗しました")
	}

	// 集計値の更新に失敗しても UVM 更新そのものは成功として返す（Python と同じ）。
	correct := 0
	for _, r := range results {
		if r.IsCorrect {
			correct++
		}
	}
	_, err = db.Collection("users").Doc(uid).Set(ctx, map[string]any{
		"last_active_at":        firestore.ServerTimestamp,
		"last_quiz_answered_at": firestore.ServerTimestamp,
		"quiz_answer_count":     firestore.Increment(len(results)),
		"quiz_correct_count":    firestore.Increment(correct),
	}, firestore.MergeAll)
	if err != nil {
		log.Printf("updateUvm metrics update failed: uid=%s, error=%v", uid, err)
	}

	log.Printf("updateUvm completed: uid=%s, updated=%d", uid, len(results))
	return map[string]any{"success": true, "updated": len(results)}, nil
}

// parseResult は results の1要素を解釈する。
//
// Python 側は r["word"] / r["is_correct"] を直接引くので、欠けていると KeyError で
// INTERNAL になる。ここでは何が悪いか分かるよう INVALID_ARGUMENT にしている
// （正常なクライアントは必ず両方を送るので、実際の挙動差は出ない）。
func parseResult(raw map[string]any) (uvm.Result, error) {
	word, ok := raw["word"].(string)
	if !ok || word == "" {
		return uvm.Result{}, callable.Errorf(callable.InvalidArgument, "word が必要です")
	}
	isCorrect, ok := raw["is_correct"].(bool)
	if !ok {
		return uvm.Result{}, callable.Errorf(callable.InvalidArgument,
			"is_correct が必要です (word=%s)", word)
	}

	// Python は isinstance(x, (int, float)) を見て int() する。JSON の数値は
	// すべて float64 で届くので、数値のときだけ切り捨てる。
	hint := 0
	switch v := raw["hint_level"].(type) {
	case float64:
		hint = int(v)
	case json.Number:
		if n, err := v.Int64(); err == nil {
			hint = int(n)
		}
	case bool:
		// Python では bool は int のサブクラスなので True が 1 になる。
		if v {
			hint = 1
		}
	}

	reviewed, _ := raw["sentence_reviewed"].(bool)

	return uvm.Result{
		Word:             word,
		IsCorrect:        isCorrect,
		HintLevel:        hint,
		SentenceReviewed: reviewed,
	}, nil
}
