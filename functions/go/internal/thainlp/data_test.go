package thainlp

import "testing"

// Python 側の初期状態を実測した値（th2ipa を1度も呼ぶ前）。
//
//	>>> import pronunciation as p; m = p._TH2IPA
//	>>> len(m.TriCount), len(m.BiCount), len(m.Count), m.TotalWord
//
// データ書き出しと導出ロジックが正しければ Go でも完全に一致する。
// ずれていたら export_tltk_data.py か loadStats() のどちらかが壊れている。
const (
	wantTriCount  = 364726
	wantBiCount   = 161490
	wantCount     = 14635
	wantTotalWord = 636693
)

func TestStatsMatchPython(t *testing.T) {
	d, err := Load()
	if err != nil {
		t.Fatalf("Load: %v", err)
	}
	s := d.Stats

	for _, c := range []struct {
		name string
		got  int
		want int
	}{
		{"TriCount", len(s.TriCount), wantTriCount},
		{"BiCount", len(s.BiCount), wantBiCount},
		{"Count", len(s.Count), wantCount},
		{"TotalWord", s.TotalWord, wantTotalWord},
	} {
		if c.got != c.want {
			t.Errorf("%s = %d, Python 実測値は %d", c.name, c.got, c.want)
		}
	}
}

func TestDataLoaded(t *testing.T) {
	d, err := Load()
	if err != nil {
		t.Fatalf("Load: %v", err)
	}
	// PyThaiNLP / TLTK の実ファイルの行数。空行を除いた数。
	if len(d.SylRule) == 0 {
		t.Error("sylrule.lts が空")
	}
	if len(d.Dict) < 30000 {
		t.Errorf("BEST.dict の語数 = %d, 33,200 前後を期待", len(d.Dict))
	}
	if len(d.Words) < 60000 {
		t.Errorf("words_th.txt の語数 = %d, 62,098 前後を期待", len(d.Words))
	}
	if len(d.Syllables) < 10000 {
		t.Errorf("syllables_th.txt = %d, 10,322 前後を期待", len(d.Syllables))
	}
	if len(d.SylVar) == 0 {
		t.Error("sylform_var.json が空")
	}
}
