package function

import (
	"testing"
	"time"
)

func TestAppVersionBefore(t *testing.T) {
	min := [3]int{1, 4, 13}
	tests := map[string]bool{
		"1.4.12": true,
		"1.4.13": false,
		"1.4.14": false,
		"1.5.0":  false,
		"1.3.99": true,
		"2.0.0":  false,
		"":       true,
		"1.4":    true,
		"abc":    true,
	}
	for version, want := range tests {
		if got := appVersionBefore(version, min); got != want {
			t.Errorf("appVersionBefore(%q) = %v, want %v", version, got, want)
		}
	}
}

func TestNeedsLegacyTrial(t *testing.T) {
	now := time.Date(2026, 9, 28, 0, 0, 0, 0, time.UTC)
	tests := []struct {
		name                 string
		data                 map[string]any
		clientUsesStoreTrial bool
		want                 bool
	}{
		{"旧アプリの新規は配る", map[string]any{"app_version": "1.4.12"}, false, true},
		{"版の記録が無い旧アプリは配る", map[string]any{}, false, true},
		{"版の書き込み前でも新アプリには配らない", map[string]any{}, true, false},
		{"doc の版が古くても新アプリには配らない", map[string]any{"app_version": "1.4.12"}, true, false},
		{"1.4.13 の新規は配らない", map[string]any{"app_version": "1.4.13"}, false, false},
		{"体験を持っていれば配らない", map[string]any{"app_version": "1.4.12", "premium_trial_expires_at": now}, false, false},
		{"生成したことがあれば配らない", map[string]any{"app_version": "1.4.12", "first_generated_at": now}, false, false},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := needsLegacyTrial(tt.data, tt.clientUsesStoreTrial); got != tt.want {
				t.Errorf("needsLegacyTrial = %v, want %v", got, tt.want)
			}
		})
	}
}
