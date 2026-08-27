package thainlp

import (
	"testing"
	"time"
)

func TestLoadColdStart(t *testing.T) {
	start := time.Now()
	if _, err := Load(); err != nil {
		t.Fatal(err)
	}
	t.Logf("Load() cold: %v", time.Since(start))

	start = time.Now()
	if _, err := ThaiToPronunciation("สวัสดีครับ"); err != nil {
		t.Fatal(err)
	}
	t.Logf("first ThaiToPronunciation: %v", time.Since(start))
}
