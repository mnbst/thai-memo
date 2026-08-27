package function

import (
	"encoding/json"
	"os"
	"reflect"
	"sort"
	"testing"
	"time"

	"cloud.google.com/go/firestore"

	"github.com/mnbst/thai-memo/functions/go/internal/premium"
	"github.com/mnbst/thai-memo/functions/go/internal/uvm"
)

// sentenceHandlersGoldenPath は
// functions/python/scripts/daily_golden/gen_handlers_golden.py の出力。
const sentenceHandlersGoldenPath = "testdata/python/daily_golden/handlers_golden.json"

type sentenceHandlersGolden struct {
	EffectiveGenerationParams []struct {
		Params    map[string]any `json:"params"`
		IsPremium bool           `json:"is_premium"`
		Want      map[string]any `json:"want"`
	} `json:"effective_generation_params"`
	CappedEstimatedVocab []struct {
		UserData  map[string]any `json:"user_data"`
		IsPremium bool           `json:"is_premium"`
		Want      int            `json:"want"`
	} `json:"capped_estimated_vocab"`
	CommitUpdate []struct {
		UserData           map[string]any `json:"user_data"`
		Decrement          int            `json:"decrement"`
		WantKeys           []string       `json:"want_keys"`
		WantRemainingDelta int            `json:"want_remaining_delta"`
		WantCountDelta     int            `json:"want_count_delta"`
	} `json:"commit_update"`
	TrialActive []struct {
		IsPremium bool    `json:"is_premium"`
		ExpiresAt *string `json:"expires_at"`
		Now       string  `json:"now"`
		Want      bool    `json:"want"`
	} `json:"trial_active"`
	CeilJSTMidnight []struct {
		Value string `json:"value"`
		Want  string `json:"want"`
	} `json:"ceil_jst_midnight"`
}

func loadSentenceHandlersGolden(t *testing.T) *sentenceHandlersGolden {
	t.Helper()
	b, err := os.ReadFile(sentenceHandlersGoldenPath)
	if err != nil {
		t.Fatalf("golden を読めない（gen_handlers_golden.py を実行したか？）: %v", err)
	}
	var g sentenceHandlersGolden
	if err := json.Unmarshal(b, &g); err != nil {
		t.Fatalf("golden の JSON 解析に失敗: %v", err)
	}
	return &g
}

func TestEffectiveGenerationParamsAgainstPythonGolden(t *testing.T) {
	g := loadSentenceHandlersGolden(t)
	for ci, c := range g.EffectiveGenerationParams {
		got := effectiveGenerationParams(c.Params, c.IsPremium)
		gotJSON, _ := json.Marshal(got)
		wantJSON, _ := json.Marshal(c.Want)
		if string(gotJSON) != string(wantJSON) {
			t.Errorf("case %d: got=%s want=%s", ci, gotJSON, wantJSON)
		}
	}
	t.Logf("生成条件の整形 %dケース一致", len(g.EffectiveGenerationParams))
}

func TestCappedEstimatedVocabAgainstPythonGolden(t *testing.T) {
	g := loadSentenceHandlersGolden(t)
	for ci, c := range g.CappedEstimatedVocab {
		got := intValue(c.UserData["estimated_vocab"])
		if !c.IsPremium {
			got = min(got, uvm.FreeTierMaxVocab)
		}
		if got != c.Want {
			t.Errorf("case %d %v premium=%v: = %d, want %d",
				ci, c.UserData, c.IsPremium, got, c.Want)
		}
	}
	t.Logf("語彙スコアの上限 %dケース一致", len(g.CappedEstimatedVocab))
}

func TestSentenceCommitUpdateAgainstPythonGolden(t *testing.T) {
	g := loadSentenceHandlersGolden(t)
	for ci, c := range g.CommitUpdate {
		updates := sentenceCommitUpdate(c.UserData, c.Decrement)
		var keys []string
		byPath := map[string]any{}
		for _, u := range updates {
			keys = append(keys, u.Path)
			byPath[u.Path] = u.Value
		}
		sort.Strings(keys)
		if !equalStrs(keys, c.WantKeys) {
			t.Fatalf("case %d: 更新キー = %v, want %v", ci, keys, c.WantKeys)
		}
		if !reflect.DeepEqual(byPath["remaining_sentences"], firestore.Increment(c.WantRemainingDelta)) {
			t.Errorf("case %d: remaining_sentences の増減が違う", ci)
		}
		if !reflect.DeepEqual(byPath["sentence_generated_count"], firestore.Increment(c.WantCountDelta)) {
			t.Errorf("case %d: sentence_generated_count の増減が違う", ci)
		}
	}
	t.Logf("クォータ消費の更新内容 %dケース一致", len(g.CommitUpdate))
}

func TestTrialActiveAgainstPythonGolden(t *testing.T) {
	g := loadSentenceHandlersGolden(t)
	for ci, c := range g.TrialActive {
		now, err := time.Parse(time.RFC3339Nano, c.Now)
		if err != nil {
			t.Fatalf("case %d: now を読めない: %v", ci, err)
		}
		userData := map[string]any{}
		if c.ExpiresAt != nil {
			expires, err := time.Parse(time.RFC3339Nano, *c.ExpiresAt)
			if err != nil {
				t.Fatalf("case %d: expires_at を読めない: %v", ci, err)
			}
			userData["premium_trial_expires_at"] = expires
		}
		got := !c.IsPremium && premium.IsTrialActive(userData, now)
		if got != c.Want {
			t.Errorf("case %d premium=%v expires=%v: = %v, want %v",
				ci, c.IsPremium, c.ExpiresAt, got, c.Want)
		}
	}
	t.Logf("トライアル判定 %dケース一致", len(g.TrialActive))
}

func TestCeilToJSTMidnightAgainstPythonGolden(t *testing.T) {
	g := loadSentenceHandlersGolden(t)
	for ci, c := range g.CeilJSTMidnight {
		value, err := time.Parse(time.RFC3339Nano, c.Value)
		if err != nil {
			t.Fatalf("case %d: value を読めない: %v", ci, err)
		}
		want, err := time.Parse(time.RFC3339Nano, c.Want)
		if err != nil {
			t.Fatalf("case %d: want を読めない: %v", ci, err)
		}
		got := time.UnixMilli(premium.CeilToJSTMidnight(value.UnixMilli())).UTC()
		if !got.Equal(want) {
			t.Errorf("case %d: %s -> %s, want %s", ci, c.Value, got, want)
		}
	}
	t.Logf("JST 0:00 への切り上げ %dケース一致", len(g.CeilJSTMidnight))
}

func equalStrs(a, b []string) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if a[i] != b[i] {
			return false
		}
	}
	return true
}
