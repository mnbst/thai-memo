package function

import (
	"context"
	"log"
	"time"

	"cloud.google.com/go/firestore"

	"github.com/mnbst/thai-memo/functions/go/internal/fbapp"
	"github.com/mnbst/thai-memo/functions/go/internal/quality"
	"github.com/mnbst/thai-memo/functions/go/internal/sentence"
)

// qualityChecker は quality.Judge（Jev）を sentence.Checker として使う包み。
//
// 生成直後に1文ずつ判定する。Jev は1文 0.5 秒前後（p95 0.6 秒）で、
// 不合格なら Producer が指摘つきで1回作り直し、もう一度ここを通す。
//
// 不合格の判定はそのつど sentence_flags へ1件書く（stage=first / retry）。
// stage=retry の記録が「作り直しても不合格でプールに入らなかった文」になる。
type qualityChecker struct {
	judge *quality.Judge
	// db が nil なら sentence_flags へは書かない（判定だけ行う）。
	db *firestore.Client
}

// newQualityChecker は判定器を組み立てる。キーが読めなければ nil を返し、
// Producer は判定なしで動く（生成を止めるほどの機能ではない）。
func newQualityChecker(ctx context.Context) sentence.Checker {
	j, err := quality.NewJudge(ctx)
	if err != nil {
		log.Printf("qualityCheck: disabled (judge unavailable): %v", err)
		return nil
	}
	db, err := fbapp.Firestore(ctx)
	if err != nil {
		log.Printf("qualityCheck: sentence_flags disabled: %v", err)
		db = nil
	}
	return &qualityChecker{judge: j, db: db}
}

// Check は 1 文を判定する。不合格なら差し戻し用の指摘を Notes に入れて返す。
func (c *qualityChecker) Check(ctx context.Context, in sentence.CheckInput) (sentence.CheckResult, error) {
	cand := quality.Candidate{
		UID:                 in.UID,
		ThaiText:            in.Sentence.ThaiText,
		Pronunciation:       in.Sentence.Pronunciation,
		JapaneseTranslation: in.Sentence.JapaneseTranslation,
		KeyWord:             in.KeyWord,
		Topic:               in.Topic,
		GenerationTier:      in.Tier,
		Lang:                in.Lang,
		CreatedAt:           time.Now(),
	}
	res, err := c.judge.Review(ctx, []quality.Candidate{cand})
	if err != nil {
		return sentence.CheckResult{}, err
	}
	if len(res.Verdicts) == 0 {
		// 合格も1行残す。作り直し率（flagged / checked）をログから数えるため。
		log.Printf("qualityCheck: passed stage=%s key_word=%s", in.Stage, in.KeyWord)
		// 合格時は Verdict が無いので確率は持たない（保存は passed だけで足りる）。
		return sentence.CheckResult{Model: c.judge.Model}, nil
	}
	v := res.Verdicts[0]
	log.Printf("qualityCheck: flagged stage=%s key_word=%s reason=%s thai=%q",
		in.Stage, in.KeyWord, v.Reason, cand.ThaiText)
	c.writeFlag(ctx, cand, v, in.Stage)
	return sentence.CheckResult{
		Notes:  v.RetryNotes(),
		Reason: v.Reason,
		Scores: v.Scores,
		Model:  c.judge.Model,
	}, nil
}

// writeFlag は不合格の判定を sentence_flags へ1件書く。失敗しても判定は続ける。
//
// doc ID は自動採番。生成時は同じ文を二度判定しない（バッチの流し直しが無い）ので、
// 固定 ID で重複を防ぐ必要がない。例文 doc はこの時点ではまだ書かれていない。
func (c *qualityChecker) writeFlag(
	ctx context.Context, cand quality.Candidate, v quality.Verdict, stage string,
) {
	if c.db == nil {
		return
	}
	doc := quality.FlagDoc(cand, v, c.judge.Model, time.Now())
	doc["stage"] = stage
	doc["lang"] = string(cand.Lang)
	if _, _, err := c.db.Collection("sentence_flags").Add(ctx, doc); err != nil {
		log.Printf("qualityCheck: write flag failed: %v", err)
	}
}
