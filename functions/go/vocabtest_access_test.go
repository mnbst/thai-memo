package function

import (
	"testing"
	"time"
)

func TestCanStartVocabTest(t *testing.T) {
	now := time.Date(2026, 9, 28, 0, 0, 0, 0, time.UTC)
	tests := []struct {
		name string
		data map[string]any
		want bool
	}{
		{"初回の free は受けられる", map[string]any{"tier": "free"}, true},
		{"測定済みの free は受けられない", map[string]any{"tier": "free", "vocab_test_at": now.Add(-time.Hour)}, false},
		{"測定済みでも premium は受けられる", map[string]any{"tier": "premium", "vocab_test_at": now.Add(-time.Hour)}, true},
		{"測定済みでも体験中は受けられる", map[string]any{"vocab_test_at": now.Add(-time.Hour), "premium_trial_expires_at": now.Add(time.Hour)}, true},
		{"体験が切れた測定済みは受けられない", map[string]any{"vocab_test_at": now.Add(-time.Hour), "premium_trial_expires_at": now.Add(-time.Minute)}, false},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := canStartVocabTest(tt.data, now); got != tt.want {
				t.Errorf("canStartVocabTest = %v, want %v", got, tt.want)
			}
		})
	}
}
