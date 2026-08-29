package thainlp

import "testing"

// Python 側の実測値。
//
//	>>> import pronunciation as p; m = p._TH2IPA
//	>>> len(m.PRON), sum(len(v) for v in m.PRON.values()), len(m.AK), len(m.EngAbbr)
const (
	wantPronPatterns = 2223
	wantPronPhones   = 2394
	wantAK           = 36
	wantEngAbbr      = 26
)

// TestSylRulesLoad は規則テーブルの移送が壊れていないことを見る。
// 2,223 本の正規表現が Go でコンパイルできるかどうかは方式の前提なので、
// 実装を書く前にここで確かめておく。
func TestSylRulesLoad(t *testing.T) {
	s, err := LoadSylRules()
	if err != nil {
		t.Fatalf("LoadSylRules: %v", err)
	}

	if len(s.Pron) != wantPronPatterns {
		t.Errorf("PRON パターン数 = %d, Python 実測値は %d", len(s.Pron), wantPronPatterns)
	}
	phones := 0
	for _, r := range s.Pron {
		phones += len(r.Phones)
	}
	if phones != wantPronPhones {
		t.Errorf("PRON 音素列の総数 = %d, Python 実測値は %d", phones, wantPronPhones)
	}
	if len(s.AK) != wantAK {
		t.Errorf("AK = %d, Python 実測値は %d", len(s.AK), wantAK)
	}
	if len(s.EngAbbr) != wantEngAbbr {
		t.Errorf("EngAbbr = %d, Python 実測値は %d", len(s.EngAbbr), wantEngAbbr)
	}

	// stable は X 系（頭子音）と Y 系（末子音）に別れ、他は別名。
	for _, k := range []string{"A", "C", "D", "E", "F", "G", "H", "K", "R", "X", "Y", "Z"} {
		if len(s.Stable[k]) == 0 {
			t.Errorf("stable[%q] が空", k)
		}
	}
	if got := s.Stable["X"]["ก"]; got != "k" {
		t.Errorf(`stable["X"]["ก"] = %q, want "k"`, got)
	}
	if got := s.Stable["Y"]["ร"]; got != "n" {
		t.Errorf(`stable["Y"]["ร"] = %q, want "n"`, got)
	}
}

// TestSylRulesMatch は先頭一致が Python の re.match と同じ形で動くことの確認。
func TestSylRulesMatch(t *testing.T) {
	s, err := LoadSylRules()
	if err != nil {
		t.Fatalf("LoadSylRules: %v", err)
	}
	// 先頭パターンは "เ(A)(K)ี[่้๊๋]*ยะ" 展開後。เดียะ のような綴りに当たる。
	hit := 0
	for _, r := range s.Pron {
		m, err := r.Match([]rune("กิน"))
		if err != nil {
			t.Fatalf("Match: %v", err)
		}
		if m != nil {
			hit++
		}
	}
	if hit == 0 {
		t.Error("กิน にどの規則も当たらない。パターン移送が壊れている可能性")
	}
	t.Logf("กิน に一致した規則: %d 本", hit)
}
