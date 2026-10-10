package function

import (
	"encoding/json"
	"fmt"
	"os"
	"testing"
	"time"

	"github.com/mnbst/thai-memo/functions/go/internal/lang"
	"github.com/mnbst/thai-memo/functions/go/internal/quality"
)

// 実 Firestore の直近の premium 例文を judge にかけ、結果を出力する。
// **書き込みはしない**（sentence_flags には触らない）。判定の当たり具合と
// reason の質を人の目で見るための dry run。
//
//	GCLOUD_PROJECT=thai-memo-prod LIVE_FIRESTORE_TEST=1 \
//	  AUDIT_LIVE_MAX=20 AUDIT_LIVE_HOURS=24 \
//	  go test -run TestSentenceAuditLive -v -timeout 10m .
//
// 認証は gcloud auth application-default login 済みであること。
// gemini-api-key は Secret Manager から引く（＝実際に課金される）。
func TestSentenceAuditLive(t *testing.T) {
	db, ctx := liveFirestore(t)

	hours := intEnvOr("AUDIT_LIVE_HOURS", 24)
	maxN := intEnvOr("AUDIT_LIVE_MAX", 20)

	users, err := allUserDocs(ctx, db)
	if err != nil {
		t.Fatal(err)
	}
	t.Logf("users=%d", len(users))

	cutoff := time.Now().Add(-time.Duration(hours) * time.Hour)
	candidates, _ := auditCandidates(ctx, db, users, cutoff)
	t.Logf("直近%dh の premium 例文=%d件", hours, len(candidates))
	if len(candidates) == 0 {
		t.Skip("対象なし")
	}
	candidates = candidates[:min(len(candidates), maxN)]

	judge, err := newJudge(ctx)
	if err != nil {
		t.Fatal(err)
	}
	t.Logf("judge=%s 判定対象=%d件", judge.Model, len(candidates))

	flaggedTotal := 0
	for _, batch := range chunkCandidates(candidates, 5) {
		hits, verdicts, err := judge.JudgeBatch(ctx, batch)
		if err != nil {
			t.Errorf("judge 失敗: %v", err)
			continue
		}
		flaggedTotal += len(hits)
		for i, c := range hits {
			fmt.Printf("\n--- flagged (uid=%s key_word=%s topic=%s)\n", c.UID, c.KeyWord, c.Topic)
			fmt.Printf("  thai     : %s\n", c.ThaiText)
			fmt.Printf("  japanese : %s\n", c.JapaneseTranslation)
			fmt.Printf("  reason   : %s\n", verdicts[i].Reason)
		}
	}

	t.Logf("判定=%d件 flagged=%d件 (%.0f%%)",
		len(candidates), flaggedTotal, float64(flaggedTotal)/float64(len(candidates))*100)
}

// TestSentenceAuditFileLive は cmd/sample が書いた JSON を judge にかける。
// Firestore を通さないので、プロンプトを直す→生成→判定のループに使える。
//
//	go run ./cmd/sample -words "ลอง,แต่ว่า" -vocab 200,800 -n 5 -out /tmp/s.json
//	AUDIT_LIVE_FILE=/tmp/s.json LIVE_FIRESTORE_TEST=1 GCLOUD_PROJECT=thai-memo-dev \
//	  go test -run TestSentenceAuditFileLive -v -timeout 10m .
func TestSentenceAuditFileLive(t *testing.T) {
	path := os.Getenv("AUDIT_LIVE_FILE")
	if path == "" || os.Getenv("LIVE_FIRESTORE_TEST") == "" {
		t.Skip("AUDIT_LIVE_FILE / LIVE_FIRESTORE_TEST が未設定")
	}

	raw, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	var records []struct {
		TargetWord  string         `json:"target_word"`
		ThaiText    string         `json:"thai_text"`
		Translation string         `json:"japanese_translation"`
		Context     map[string]any `json:"context"`
		Error       string         `json:"error"`
	}
	if err := json.Unmarshal(raw, &records); err != nil {
		t.Fatal(err)
	}

	var candidates []quality.Candidate
	for i, r := range records {
		if r.Error != "" || r.ThaiText == "" {
			continue
		}
		topic, _ := r.Context["topic"].(string)
		candidates = append(candidates, quality.Candidate{
			SentenceID:          fmt.Sprintf("%d", i),
			ThaiText:            r.ThaiText,
			JapaneseTranslation: r.Translation,
			KeyWord:             r.TargetWord,
			Topic:               topic,
		})
	}
	if len(candidates) == 0 {
		t.Fatal("判定できる文が無い")
	}

	ctx := t.Context()
	judge, err := newJudge(ctx)
	if err != nil {
		t.Fatal(err)
	}
	t.Logf("judge=%s 判定対象=%d件", judge.Model, len(candidates))

	flaggedTotal := 0
	for _, batch := range chunkCandidates(candidates, 5) {
		hits, verdicts, err := judge.JudgeBatch(ctx, batch)
		if err != nil {
			t.Errorf("judge 失敗: %v", err)
			continue
		}
		flaggedTotal += len(hits)
		for i, c := range hits {
			fmt.Printf("\n--- flagged [%s] key_word=%s topic=%s\n", c.SentenceID, c.KeyWord, c.Topic)
			fmt.Printf("  thai     : %s\n", c.ThaiText)
			fmt.Printf("  japanese : %s\n", c.JapaneseTranslation)
			fmt.Printf("  reason   : %s\n", verdicts[i].Reason)
		}
	}
	t.Logf("判定=%d件 flagged=%d件 (%.0f%%)",
		len(candidates), flaggedTotal, float64(flaggedTotal)/float64(len(candidates))*100)
}

// TestSentencePoolBackfillLive は過去の LLM 生成例文をティアのプールへ取り込む。
// dailyBatch は直近24時間しか見ないので、プールを分ける前の文はこれで入れる。
//
// 生成時の判定（quality）が不合格の文は入れない。判定の無い古い文は、
// 生成時の観点（Aspects）で判定し直してから、プール用の観点にかける。
// lang を持たない古い doc は、訳文の文字で ja / en を決める（片方の言語として
// だけ読める訳に限る。どちらとも言えない文は入れない）。
// 既定は dry run。POOL_BACKFILL_WRITE=1 で GCS へ書く。
//
//	GCLOUD_PROJECT=thai-memo-prod LIVE_FIRESTORE_TEST=1 \
//	  POOL_BACKFILL_TIER=free POOL_BACKFILL_DAYS=365 \
//	  go test -run TestSentencePoolBackfillLive -v -timeout 20m .
func TestSentencePoolBackfillLive(t *testing.T) {
	db, ctx := liveFirestore(t)
	tier := envOr("POOL_BACKFILL_TIER", "free")
	days := intEnvOr("POOL_BACKFILL_DAYS", 365)

	users, err := allUserDocs(ctx, db)
	if err != nil {
		t.Fatal(err)
	}
	cutoff := time.Now().AddDate(0, 0, -days)
	all, docs := auditCandidates(ctx, db, users, cutoff)

	var passed, unjudged []quality.Candidate
	rejected, inferred, unknown := 0, 0, 0
	for _, c := range all {
		if c.GenerationTier != tier {
			continue
		}
		data := docs[quality.FlagID(c)]
		if _, ok := lang.Parse(stringField(data["lang"])); !ok {
			l, ok := inferTranslationLang(c.JapaneseTranslation)
			if !ok {
				unknown++
				continue
			}
			// メモリ上の doc に載せるだけで、Firestore には書かない。
			data["lang"] = string(l)
			c.Lang = l
			inferred++
		}
		switch v, _ := poolVerdictOf(docs[quality.FlagID(c)]); v {
		case poolPassed:
			passed = append(passed, c)
		case poolUnjudged:
			unjudged = append(unjudged, c)
		default:
			rejected++
		}
	}
	t.Logf("tier=%s 直近%d日: 合格=%d 未判定=%d 不合格=%d（lang を訳文から決めた %d・決められず外した %d）",
		tier, days, len(passed), len(unjudged), rejected, inferred, unknown)

	judge, err := newJudge(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if len(unjudged) > 0 {
		res, err := judge.Review(ctx, unjudged)
		if err != nil {
			t.Logf("未判定の判定に一部失敗: %v", err)
		}
		for i, c := range res.Flagged {
			fmt.Printf("drop(生成時の観点) key_word=%s %s | %s | %s\n",
				c.KeyWord, res.Verdicts[i].Reason, c.ThaiText, c.JapaneseTranslation)
		}
		passed = append(passed, res.Accepted...)
	}
	accepted := poolGate(ctx, judge, passed)

	entries := 0
	for _, c := range accepted {
		if _, ok := buildPoolEntry(docs[quality.FlagID(c)]); ok {
			entries++
		}
	}
	t.Logf("プールへ入れる=%d件（lang 等が欠けて外れる %d件）", entries, len(accepted)-entries)

	if os.Getenv("POOL_BACKFILL_WRITE") != "1" {
		t.Log("dry run（POOL_BACKFILL_WRITE=1 で書く）")
		return
	}
	if err := poolAccepted(ctx, accepted, docs); err != nil {
		t.Fatal(err)
	}
}

// inferTranslationLang は訳文がどちらの言語で書かれているかを決める。
// 片方の言語としてだけ読めるときに限って返す。
func inferTranslationLang(text string) (lang.Lang, bool) {
	ja := !lang.IsWrongLanguage(text, lang.JA)
	en := !lang.IsWrongLanguage(text, lang.EN)
	switch {
	case ja && !en:
		return lang.JA, true
	case en && !ja:
		return lang.EN, true
	}
	return "", false
}
