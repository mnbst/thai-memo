package thainlp

import "testing"

// TestShortVowelIsNotLengthened は、tltk/thaisyl.dict が短母音の綴りに
// 長母音の読みを与えていた音節を見る。いずれも ไม้โท（้）付きの
// ไ-/ใ-/เ-า 音節で、下降声・高声として現れていた。
//
//	ได้ -> daaj2（"dâai"）／正しくは daj2（"dâi"）
//
// 修正は Python 側 pronunciation.py:_SYLDICT_VOWEL_FIXES にあり、
// data/sylrule_pron.json は export_tltk_data.py 経由でそれを取り込む。
// Python の tests/test_nlp.py::test_short_vowel_is_not_lengthened と同じ表。
func TestShortVowelIsNotLengthened(t *testing.T) {
	cases := []struct{ in, want string }{
		{"ได้", "dâi"},
		{"ใต้", "tâi"},
		{"ไม้", "mái"},
		{"มั้ย", "mái"},
		{"เจ้า", "jâw"},
		{"เกล้า", "klâw"},
		{"เท้า", "tháw"},
		{"ข้าพเจ้า", "khâa-phá-jâw"},
		{"ต้นไม้", "tôn-mái"},
		{"ได้ไหม", "dâi-mǎi"},
		// 本来の長母音は縮めない
		{"สาย", "sǎai"},
		{"สุดท้าย", "sùt-tháai"},
	}
	for _, c := range cases {
		got, err := ThaiToPronunciation(c.in)
		if err != nil {
			t.Errorf("ThaiToPronunciation(%q): %v", c.in, err)
			continue
		}
		if got != c.want {
			t.Errorf("ThaiToPronunciation(%q) = %q, want %q", c.in, got, c.want)
		}
	}
}
