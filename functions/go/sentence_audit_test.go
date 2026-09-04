package function

import (
	"testing"
	"time"

	"github.com/mnbst/thai-memo/functions/go/internal/quality"
)

func TestCandidateFromSkipsNonPremium(t *testing.T) {
	created := time.Date(2026, 9, 1, 3, 0, 0, 0, time.UTC)
	premium := map[string]any{
		"generation_tier":      "premium",
		"thai_text":            "ผมกินข้าว",
		"pronunciation":        "phom kin khao",
		"japanese_translation": "ご飯を食べます",
		"key_word":             "กิน",
		"context":              map[string]any{"topic": "食べ物", "emotion": "neutral"},
		"created_at":           created,
	}

	c, ok := candidateFrom("u1", "s1", premium)
	if !ok {
		t.Fatal("premium は対象のはず")
	}
	if c.UID != "u1" || c.SentenceID != "s1" || c.Topic != "食べ物" ||
		c.Emotion != "neutral" || !c.CreatedAt.Equal(created) {
		t.Errorf("読み取りが欠けている: %+v", c)
	}

	free := map[string]any{"generation_tier": "free", "thai_text": "ผมกินข้าว"}
	if _, ok := candidateFrom("u1", "s1", free); ok {
		t.Error("free を対象にしている")
	}

	// generation_tier を持たない旧 doc も対象外（premium と断定できない）。
	if _, ok := candidateFrom("u1", "s1", map[string]any{"thai_text": "ผมกินข้าว"}); ok {
		t.Error("tier 不明の doc を対象にしている")
	}

	// 本文が無い doc は判定に出せない。
	empty := map[string]any{"generation_tier": "premium", "thai_text": ""}
	if _, ok := candidateFrom("u1", "s1", empty); ok {
		t.Error("本文が空の doc を対象にしている")
	}
}

func TestSampleCandidatesCapsAndMixes(t *testing.T) {
	in := make([]quality.Candidate, 50)
	for i := range in {
		in[i] = quality.Candidate{UID: string(rune('a' + i%26)), SentenceID: string(rune('A' + i%26))}
	}

	if got := sampleCandidates(in, 100); len(got) != 50 {
		t.Errorf("上限未満はそのまま返す: %d", len(got))
	}
	got := sampleCandidates(in, 10)
	if len(got) != 10 {
		t.Fatalf("上限まで間引かれていない: %d", len(got))
	}
}

func TestChunkCandidates(t *testing.T) {
	in := make([]quality.Candidate, 12)
	got := chunkCandidates(in, 5)
	if len(got) != 3 {
		t.Fatalf("3束のはず: %d", len(got))
	}
	if len(got[0]) != 5 || len(got[2]) != 2 {
		t.Errorf("端数の扱いが違う: %d %d", len(got[0]), len(got[2]))
	}
	if chunkCandidates(nil, 5) != nil {
		t.Error("空は nil")
	}
}

func TestIntEnvOr(t *testing.T) {
	if got := intEnvOr("SENTENCE_AUDIT_MAX_UNSET_FOR_TEST", 100); got != 100 {
		t.Errorf("未設定は既定値: %d", got)
	}
	t.Setenv("SENTENCE_AUDIT_MAX_FOR_TEST", "0")
	if got := intEnvOr("SENTENCE_AUDIT_MAX_FOR_TEST", 100); got != 0 {
		t.Errorf("0（無効化）を既定値で潰している: %d", got)
	}
	t.Setenv("SENTENCE_AUDIT_MAX_FOR_TEST", "ten")
	if got := intEnvOr("SENTENCE_AUDIT_MAX_FOR_TEST", 100); got != 100 {
		t.Errorf("不正値は既定値: %d", got)
	}
}
