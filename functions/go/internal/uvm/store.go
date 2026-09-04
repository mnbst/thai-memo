package uvm

import (
	"context"
	"fmt"
	"log"
	"math"
	"time"

	"cloud.google.com/go/firestore"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

// Result はクイズ1問分の結果。クライアントから callable の data.results で届く。
type Result struct {
	Word string `json:"word"`
	// IsCorrect は Python では r["is_correct"]（欠けていれば KeyError）。
	IsCorrect bool `json:"is_correct"`
	// HintLevel は数値でないときは 0 扱い（Python の isinstance チェック相当）。
	HintLevel int `json:"-"`
	// SentenceReviewed は真のときだけ α を弱める。
	SentenceReviewed bool `json:"sentence_reviewed"`
}

// IsGradedResult は「等倍で採点されたクイズの回答」かを返す。
//
// 境界推定（SyncEstimatedVocab）の母数はこれが真の語だけ。確認クイズ
// （quiz_type=="learning"）の正解は α×0.1、ヒント有りは ×0.5/×0.25、例文
// レビュー由来も ×0.1 で、P は VocabCutoffP=0.42 に構造的に届かない。それでも
// MovingAvg の母数には入るので、未登録 rank の prior(0.4) より低い実測値として
// 平均を押し下げ、例文を生成するたびに境界が数ランク落ちていた。
//
// 減衰つきの回答は P だけ動かし、境界の証拠にはしない。
func IsGradedResult(quizType string, r Result) bool {
	return quizType != "learning" && r.HintLevel == 0 && !r.SentenceReviewed
}

// now は time.time() 相当（Unix 秒の float）。Firestore には数値で入る。
func nowSeconds() float64 {
	return float64(time.Now().UnixNano()) / 1e9
}

// BatchUpdate はクイズ/例文の正誤結果をもとに UVM を一括更新する
// （uvm.py:batch_update_uvm）。
//
// 既存の UVM ドキュメントがあれば P を更新、なければ新規作成する。
// freqRank が非 nil のときは続けて estimated_vocab を同期する。
func BatchUpdate(
	ctx context.Context,
	db *firestore.Client,
	uid string,
	results []Result,
	freqRank map[string]int,
	quizType string,
	isPremium bool,
) error {
	now := nowSeconds()
	uvmRef := db.Collection("users").Doc(uid).Collection("uvm")

	// 全単語のドキュメントを一括取得
	refs := make([]*firestore.DocumentRef, 0, len(results))
	for _, r := range results {
		refs = append(refs, uvmRef.Doc(r.Word))
	}
	snaps, err := db.GetAll(ctx, refs)
	if err != nil {
		return fmt.Errorf("uvm の一括取得に失敗: %w", err)
	}
	existing := make(map[string]map[string]any, len(snaps))
	for _, s := range snaps {
		if s.Exists() {
			existing[s.Ref.ID] = s.Data()
		}
	}

	batch := db.BulkWriter(ctx)
	for _, r := range results {
		docRef := uvmRef.Doc(r.Word)

		var rank *int
		if v, ok := freqRank[r.Word]; ok {
			rank = &v
		}

		mult := HintMultiplier(r.HintLevel)
		if quizType == "learning" && r.IsCorrect {
			mult *= LearningCorrectMultiplier
		}
		if r.SentenceReviewed && r.IsCorrect {
			mult *= SentenceReviewCorrectMultiplier
		}

		graded := IsGradedResult(quizType, r)

		if data, ok := existing[r.Word]; ok {
			// --- 既存単語の更新 ---
			oldP := floatField(data, "p", NewWordP)
			attempts := intField(data, "quiz_attempts", 0)
			newP := UpdateP(oldP, r.IsCorrect, attempts, rank, mult)
			updates := []firestore.Update{
				{Path: "p", Value: newP},
				{Path: "quiz_attempts", Value: attempts + 1},
				{Path: "last_seen", Value: now},
				{Path: "last_result", Value: r.IsCorrect},
			}
			// 一度立った graded は下ろさない（等倍で解いた事実は消えない）。
			if graded {
				updates = append(updates, firestore.Update{Path: "graded", Value: true})
			}
			if _, err := batch.Update(docRef, updates); err != nil {
				return fmt.Errorf("uvm の更新に失敗 (%s): %w", r.Word, err)
			}
		} else {
			// --- 新規単語の作成（初めて見た単語） ---
			newP := UpdateP(NewWordP, r.IsCorrect, 0, rank, mult)
			if _, err := batch.Set(docRef, map[string]any{
				"word":          r.Word,
				"p":             newP,
				"quiz_attempts": 1,
				"last_seen":     now,
				"last_result":   r.IsCorrect,
				"graded":        graded,
			}); err != nil {
				return fmt.Errorf("uvm の作成に失敗 (%s): %w", r.Word, err)
			}
		}
	}
	batch.End()

	if freqRank != nil {
		maxVocab := -1 // 負値は「上限なし」（Python の None 相当）
		if !isPremium {
			maxVocab = FreeTierMaxVocab
		}
		SyncEstimatedVocab(ctx, db, uid, freqRank, maxVocab)
	}
	return nil
}

// SyncEstimatedVocab は users/{uid} の estimated_vocab を更新する
// （uvm.py:sync_estimated_vocab）。
//
// 現在値を中心に freq_rank ±50 の語だけ UVM から引いて再計算する（全件取得を避ける）。
// maxVocab が負のときは上限なし。
func SyncEstimatedVocab(
	ctx context.Context,
	db *firestore.Client,
	uid string,
	freqRank map[string]int,
	maxVocab int,
) {
	userRef := db.Collection("users").Doc(uid)

	current, tested := 0, 0
	if snap, err := userRef.Get(ctx); err == nil && snap.Exists() {
		data := snap.Data()
		current = intField(data, "estimated_vocab", 0)
		// 語彙テストの測定値は「原点」。これ以下の rank は存在しないものとして扱う
		// （EstimateVocab の floor）。未受験は 0。
		tested = intField(data, "vocab_test_vocab", 0)
	}
	// free（maxVocab あり）は測定値を使わない。key_word 帯（GetSessionWords）が
	// free では原点シフトしないので、走査帯の下端も揃えないと帯がずれる。
	if maxVocab >= 0 {
		tested = 0
	}

	scanLow := max(tested, current-50)
	scanHigh := current + 51

	uvmRef := userRef.Collection("uvm")
	var refs []*firestore.DocumentRef
	rankOf := map[string]int{}
	for word, rank := range freqRank {
		if rank >= scanLow && rank < scanHigh {
			refs = append(refs, uvmRef.Doc(word))
			rankOf[word] = rank
		}
	}

	var entries []RankedP
	if len(refs) > 0 {
		snaps, err := db.GetAll(ctx, refs)
		if err != nil {
			log.Printf("sync_estimated_vocab: uvm の取得に失敗: uid=%s error=%v", uid, err)
			return
		}
		for _, s := range snaps {
			if !s.Exists() {
				continue
			}
			// 等倍で採点された語だけを境界の証拠にする（IsGradedResult）。
			// フィールドを持たない既存 doc は真として扱う。移行中に過去の
			// 母数が急に減って estimated_vocab が動くのを避ける。
			if !boolField(s.Data(), "graded", true) {
				continue
			}
			entries = append(entries, RankedP{
				Rank: rankOf[s.Ref.ID],
				P:    floatField(s.Data(), "p", NewWordP),
			})
		}
	}

	// 推定値をそのまま採用する。以前は 1 sync あたり ±3 に刻んでいたが、
	// 刻んでも行き先は変わらず、到達までの十数回の sync に効果が分散する
	// だけだった。クイズ 1 回の結果が、そのあとの例文生成のたびに少しずつ
	// スコアを動かしているように見えていたのはこのため。
	raw := EstimateVocab(entries, current, tested)
	estimated := max(0, raw)
	if maxVocab >= 0 {
		estimated = min(estimated, maxVocab)
	}
	log.Printf("sync_estimated_vocab: uid=%s current=%d floor=%d entries=%d raw=%d -> %d",
		uid, current, tested, len(entries), raw, estimated)

	if _, err := userRef.Set(ctx, map[string]any{"estimated_vocab": estimated},
		firestore.MergeAll); err != nil {
		log.Printf("sync_estimated_vocab: 書き込みに失敗: uid=%s error=%v", uid, err)
		return
	}
	PublishLeaderboardVocab(ctx, db, uid, estimated)
}

// PublishLeaderboardVocab は語彙スコアをランキング用の公開コレクションへ複製する
// （uvm.py:publish_leaderboard_vocab）。
//
// users/{uid} は本人しか読めないため leaderboard/{uid} を別に持つ。
// 表示名は最初の1回だけ自動採番し、以降は触らない。
// free は estimated_vocab 自体がキャップ済みなので、ここでは追加のキャップをしない。
// ランキングの失敗で呼び出し元を止めない（Python と同じくエラーを飲む）。
func PublishLeaderboardVocab(ctx context.Context, db *firestore.Client, uid string, vocab int) {
	ref := db.Collection("leaderboard").Doc(uid)

	payload := map[string]any{"vocab": vocab, "updated_at": nowSeconds()}

	hasNickname := false
	if snap, err := ref.Get(ctx); err == nil && snap.Exists() {
		if s, ok := snap.Data()["nickname"].(string); ok && s != "" {
			hasNickname = true
		}
	}
	if !hasNickname {
		if name := assignNickname(ctx, db, uid); name != "" {
			payload["nickname"] = name
		}
	}

	if _, err := ref.Set(ctx, payload, firestore.MergeAll); err != nil {
		log.Printf("publish_leaderboard_vocab failed: %v", err)
	}
}

func isAlreadyExists(err error) bool {
	return status.Code(err) == codes.AlreadyExists
}

// floatField は Firestore の数値フィールドを float64 で読む。
// Firestore は整数を int64 で返すので両方を受ける。
func floatField(data map[string]any, key string, fallback float64) float64 {
	switch v := data[key].(type) {
	case float64:
		return v
	case int64:
		return float64(v)
	case int:
		return float64(v)
	}
	return fallback
}

func boolField(data map[string]any, key string, fallback bool) bool {
	if v, ok := data[key].(bool); ok {
		return v
	}
	return fallback
}

func intField(data map[string]any, key string, fallback int) int {
	switch v := data[key].(type) {
	case int64:
		return int(v)
	case int:
		return v
	case float64:
		return int(math.Trunc(v))
	}
	return fallback
}
