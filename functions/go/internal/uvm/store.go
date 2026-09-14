package uvm

import (
	"context"
	"fmt"
	"log"
	"math"
	"time"

	"cloud.google.com/go/firestore"

	"github.com/mnbst/thai-memo/functions/go/internal/premium"
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

// IsGradedResult は「採点として扱えるクイズの回答」かを返す。
//
// 境界推定（SyncEstimatedVocab）の母数はこれが真の語だけ。確認クイズ
// （quiz_type=="learning"）は例文を読んだ直後の1問で、答えが目の前にある。
// 正解しても知っている証拠にならないので母数に入れない。
//
// ヒント・例文レビューはここでは外さない。GuessRate と
// SentenceReviewCorrectMultiplier が既に P の動きを弱めて「弱い証拠」として
// 扱っており、さらに母数から外すと同じ理由で二重に罰することになる。
// 除外は中立ではなく、MovingAvg で未登録 rank の prior(0.4) に差し替える
// 操作なので、ヒントを常用するユーザーほど母数が prior だけになり
// estimated_vocab が動かなくなっていた。ヒント2段（訳を表示）でなお
// 不正解、という最も強い「知らない」証拠まで捨てていたのも同じ理由。
func IsGradedResult(quizType string, r Result) bool {
	return quizType != "learning"
}

// ResultEvidence は回答 1 件の証拠量（等倍のまとめクイズ何問分か）を返す。
// 累積したものが uvm doc の evidence で、境界推定の母数に入れるかを決める。
//
// **正誤を見てはいけない。** α 側の倍率は正解時だけ弱める（確認クイズの正解は
// ×0.1 だが不正解は等倍）が、それを証拠量に流用すると「確認クイズは不正解だけ
// が境界推定に届く」となり、母数が結果で選別される＝下方バイアスになる。
// ここは回答の条件（ヒント段階・quiz_type・例文レビュー）だけで決める。
func ResultEvidence(quizType string, r Result) float64 {
	ev := HintMultiplier(r.HintLevel)
	if quizType == "learning" {
		ev *= LearningCorrectMultiplier
	}
	if r.SentenceReviewed {
		ev *= SentenceReviewCorrectMultiplier
	}
	return ev
}

// evidenceField は uvm doc から累積証拠量を読む。0 なら「一度も答えていない」。
//
// evidence を持たない移行前の doc は graded から導く。graded=true（および
// フィールドごと無い旧 doc）は正の値＝従来どおり母数に入れ、露出だけで
// 作られた graded=false は 0 ＝ 未登録と同じ扱い。これで移行中に母数が動かない。
func evidenceField(data map[string]any) float64 {
	if v := floatField(data, "evidence", -1); v >= 0 {
		return v
	}
	if boolField(data, "graded", true) {
		return 1
	}
	return 0
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

		// weight は証拠の重み（UpdateP の尤度比の指数）。ヒントは weight では
		// なく GuessRate 側で入るので、ここでは掛けない。
		weight := 1.0
		if quizType == "learning" && r.IsCorrect {
			weight *= LearningCorrectMultiplier
		}
		if r.SentenceReviewed && r.IsCorrect {
			weight *= SentenceReviewCorrectMultiplier
		}

		graded := IsGradedResult(quizType, r)
		ev := ResultEvidence(quizType, r)

		if data, ok := existing[r.Word]; ok {
			// --- 既存単語の更新 ---
			oldP := floatField(data, "p", NewWordP)
			attempts := intField(data, "quiz_attempts", 0)
			newP := UpdateP(oldP, r.IsCorrect, r.HintLevel, weight)
			updates := []firestore.Update{
				{Path: "p", Value: newP},
				{Path: "quiz_attempts", Value: attempts + 1},
				{Path: "evidence", Value: evidenceField(data) + ev},
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
			newP := UpdateP(NewWordP, r.IsCorrect, r.HintLevel, weight)
			if _, err := batch.Set(docRef, map[string]any{
				"word":          r.Word,
				"p":             newP,
				"quiz_attempts": 1,
				"evidence":      ev,
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
		SyncEstimatedVocab(ctx, db, uid, freqRank)
	}
	return nil
}

// SyncEstimatedVocab は users/{uid} の estimated_vocab を更新する
// （uvm.py:sync_estimated_vocab）。
//
// 現在値を中心に freq_rank ±50 の語だけ UVM から引いて再計算する（全件取得を避ける）。
// 実効freeでは従来どおり [FreeTierMaxVocab] を上限にする。購入・復元直後に
// tierだけ反映が遅れている場合は、subscriptionを含む実効権利でpremium判定する。
func SyncEstimatedVocab(
	ctx context.Context,
	db *firestore.Client,
	uid string,
	freqRank map[string]int,
) {
	userRef := db.Collection("users").Doc(uid)

	snap, err := userRef.Get(ctx)
	if err != nil {
		// 権利・現在値を読めない状態で free/0 と推測して書くと、premium の
		// estimated_vocab を100以下へ破壊する。次回の同期へ回す。
		log.Printf("sync_estimated_vocab: user の取得に失敗: uid=%s error=%v", uid, err)
		return
	}
	if !snap.Exists() {
		log.Printf("sync_estimated_vocab: user が存在しないため中止: uid=%s", uid)
		return
	}
	userData := snap.Data()
	current := intField(userData, "estimated_vocab", 0)
	// 語彙テストの測定値は「原点」。これ以下の rank は存在しないものとして扱う
	// （EstimateVocab の floor）。未受験は 0。
	tested := intField(userData, "vocab_test_vocab", 0)
	isPremium := estimatedVocabCap(userData, time.Now()) < 0
	if !isPremium {
		// free の key_word 帯は原点シフトしないため、走査帯も同じ基準に揃える。
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
			// 一度も答えていない語（例文に出ただけ）は母数から外す。P は
			// prior のままなので、MovingAvg に prior を埋めさせるのと同じ
			// 寄与になる。EstimateVocab 側の n や中心計算を揺らさないよう
			// 明示的に落とす。
			//
			// 証拠の弱さは P そのものが持っている。UpdateP は尤度比の指数に
			// weight を、推測率に GuessRate を使うので、ヒント付きや確認クイズ
			// だけの語は prior 付近から動かない。ここでさらに prior へ寄せる
			// （旧 ShrinkP）と二重の割引になり、ヒントを常用するユーザーの
			// estimated_vocab が実力より低く出ていた（真値350・ヒント2段で
			// d90 129 対 167）。
			if evidenceField(s.Data()) <= 0 {
				continue
			}
			entries = append(entries, RankedP{
				Rank: rankOf[s.Ref.ID],
				P:    floatField(s.Data(), "p", NewWordP),
			})
		}
	}

	// 帯に証拠が1つも無ければ触らない。EstimateVocab は母数ゼロのとき floor
	// （未受験なら 0）を返すので、そのまま書くと積み上げたスコアが消える。
	// free の帯（key_word は 100 以下）しか答えていない人の estimated_vocab が
	// 300 台のまま残っている、といった組み合わせで起きる。
	if len(entries) == 0 {
		if !isPremium && current > FreeTierMaxVocab {
			if _, err := userRef.Set(ctx,
				map[string]any{"estimated_vocab": FreeTierMaxVocab}, firestore.MergeAll); err != nil {
				log.Printf("sync_estimated_vocab: free上限の書き込みに失敗: uid=%s error=%v", uid, err)
				return
			}
			PublishLeaderboardVocab(ctx, db, uid, FreeTierMaxVocab)
			return
		}
		log.Printf("sync_estimated_vocab: 帯に証拠が無いため据え置き: uid=%s current=%d floor=%d",
			uid, current, tested)
		return
	}

	// 推定値をそのまま採用する。以前は 1 sync あたり ±3 に刻んでいたが、
	// 刻んでも行き先は変わらず、到達までの十数回の sync に効果が分散する
	// だけだった。クイズ 1 回の結果が、そのあとの例文生成のたびに少しずつ
	// スコアを動かしているように見えていたのはこのため。
	raw := EstimateVocab(entries, current, tested)
	estimated := max(0, raw)
	if !isPremium {
		estimated = min(estimated, FreeTierMaxVocab)
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

// estimatedVocabCap は永続化する語彙推定値の上限。負値は上限なし。
// tier反映待ちはsubscriptionから補完し、有効な購入者をfreeへ落とさない。
func estimatedVocabCap(userData map[string]any, now time.Time) int {
	if premium.IsEffectivePremium(userData, now) {
		return -1
	}
	return FreeTierMaxVocab
}

// PublishLeaderboardVocab は語彙スコアをランキング用の公開コレクションへ複製する
// （uvm.py:publish_leaderboard_vocab）。
//
// users/{uid} は本人しか読めないため leaderboard/{uid} を別に持つ。
// 表示名は最初の1回だけ自動採番し、以降は触らない。
// free は estimated_vocab 自体がキャップ済みなので、ここでは追加で加工しない。
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
