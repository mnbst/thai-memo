package sentence

import "testing"

// TestBuildSentenceDocViewed は viewed を付けるのが TrackViewed のときだけ
// であることを確かめる。旧クライアント宛ての doc にフィールドが混ざると、
// 誰も既読にしないまま出題候補から外れ続ける。
func TestBuildSentenceDocViewed(t *testing.T) {
	s := &Sentence{ThaiText: "ฉันกินข้าว"}

	doc := s.BuildSentenceDoc(DocMeta{KeyWord: "กิน"})
	if _, ok := doc["viewed"]; ok {
		t.Error("TrackViewed=false なのに viewed が入っている")
	}

	doc = s.BuildSentenceDoc(DocMeta{KeyWord: "กิน", TrackViewed: true})
	if viewed, ok := doc["viewed"].(bool); !ok || viewed {
		t.Errorf("TrackViewed=true では viewed=false で保存する: %v", doc["viewed"])
	}
}

// TestSupportsViewTracking は既読を書けるクライアントの版の境目を固定する。
func TestSupportsViewTracking(t *testing.T) {
	cases := []struct {
		version string
		want    bool
	}{
		{"1.4.11", true},
		{"1.5.0", true},
		{"2.0.0", true},
		// 1.4.10 は公開済みだが既読を書かない。
		{"1.4.10", false},
		{"1.4.9", false},
		{"1.3.99", false},
		{"", false},
		{"1.4", false},
	}
	for _, c := range cases {
		got := SupportsViewTracking(map[string]any{"app_version": c.version})
		if got != c.want {
			t.Errorf("SupportsViewTracking(%q) = %v, want %v", c.version, got, c.want)
		}
	}
	if SupportsViewTracking(map[string]any{}) {
		t.Error("版が記録されていないユーザーは対象外にする")
	}
}
