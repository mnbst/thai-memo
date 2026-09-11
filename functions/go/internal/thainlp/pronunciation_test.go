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

// TestClusterIsNotSplitIntoFinal は、先行母音 + 子音結合の綴りで結合が
// 末子音に解けてしまう音節を見る。tltk の統計はコーパス頻度で候補を選ぶため、
// 綴りが学習コーパスに無いと正しい候補があっても負ける。
//
//	แผล -> phxxn4（"phɛ̌ɛn"）／正しくは phlxx4（"phlɛ̌ɛ"）
//
// 修正は wordparse.go:sylPhoneFix。同型の綴りを巻き込んでいないことも見る。
func TestClusterIsNotSplitIntoFinal(t *testing.T) {
	cases := []struct{ in, want string }{
		{"แผล", "phlɛ̌ɛ"},
		{"แผลนี้เจ็บมาก", "phlɛ̌ɛ-níi-jèp-mâak"},
		// ล が本当に末子音の綴りは変えない
		{"แผน", "phɛ̌ɛn"},
		{"ผล", "phǒn"},
		{"เจล", "jeen"},
		// 同型で元から結合が残る綴り
		{"เพล", "phlee"},
		{"แปล", "plɛɛ"},
		{"เผลอ", "phlə̌ə"},
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
