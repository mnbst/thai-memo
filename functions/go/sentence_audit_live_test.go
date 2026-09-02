package function

import (
	"encoding/json"
	"fmt"
	"os"
	"testing"
	"time"

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
	candidates := auditCandidates(ctx, db, users, cutoff)
	t.Logf("直近%dh の premium 例文=%d件", hours, len(candidates))
	if len(candidates) == 0 {
		t.Skip("対象なし")
	}
	candidates = sampleCandidates(candidates, maxN)

	judge, err := newJudge(ctx)
	if err != nil {
		t.Fatal(err)
	}
	t.Logf("judge=%s 判定対象=%d件", judge.Model, len(candidates))

	flaggedTotal := 0
	for _, batch := range chunkCandidates(candidates, auditBatchSize) {
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
	for _, batch := range chunkCandidates(candidates, auditBatchSize) {
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
