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
		// 同型で元から結合が残る綴り（เพล は綴りどおりに読まない語なので pronunciationOverrides で pheen）
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

// TestLinkingSyllableTakesFinalConsonant は、末子音をもう一度頭子音として
// 読む音節（ฆาต|ตะ）を見る。tltk の音節辞書が ฆาต に khaat2'ka1 を
// 与えており、つなぎの音節が ต ではなく ก で読まれていた。
//
//	ฆาตกร -> "khâat-kà-kɔɔn"／正しくは "khâat-tà-kɔɔn"
//
// 修正は wordparse.go:sylPhoneRewrite。
func TestLinkingSyllableTakesFinalConsonant(t *testing.T) {
	cases := []struct{ in, want string }{
		{"ฆาตกร", "khâat-tà-kɔɔn"},
		{"ฆาตกรรม", "khâat-tà-kam"},
		{"ราชการ", "râat-chá-kaan"},
		{"ผลไม้", "phǒn-lá-mái"},
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

// TestPronunciationOverrides は綴りどおりに読まない語（pronunciationOverrides）を見る。
func TestPronunciationOverrides(t *testing.T) {
	cases := []struct{ in, want string }{
		{"เพล", "pheen"},
		{"คลิป", "khlíp"},
		{"สมาธิ", "sà-maa-thí"},
		{"สเปรย์", "sà-pree"},
		// 語頭の ส を sà と読む綴り（reSaCluster）
		{"สตรีม", "sà-triim"},
		{"สตรี", "sà-trii"},
		{"สตอรี่", "sà-tɔɔ-rîi"},
		{"สกอร์", "sà-kɔɔ"},
		{"สปอนเซอร์", "sà-pɔɔn-sə̂ə"},
		{"พีช", "phíit"},
		{"ทริป", "thríp"},
		// 短母音の開音節＋「子音＋前置母音」は子音を末子音にする（strandedConsonant）
		{"วินเทจ", "win-thêet"},
		{"วินโดวส์", "win-doow"},
		{"วิดเจ็ต", "wít-jèt"},
		{"ทีมเวิร์ก", "thiim-wə̂ək"},
		{"ฟรีสไตล์", "frii-sà-tai"},      // 長母音＋ส は当てない
		{"มีมโนธรรม", "mii-má-noo-tham"}, // strandedExempt
		// เCอร์ は1音節（hasSplitSaraOe・addSaraOeKaran）。เก|อร์ と切らない
		{"ล็อกเกอร์", "lɔ́k-kəə"},
		{"ตู้ล็อกเกอร์", "tûu-lɔ́k-kəə"},
		{"เบอร์เกอร์", "bəə-kəə"},
		{"เกอร์คิน", "kəə-khin"},
		{"แอนอเมอร์", "ɛɛn-à-məə"},
		{"เดอร์", "dəə"}, // 規則表にある綴りは変えない
		{"ลิขสิทธิ์", "lík-khà-sìt"},
		// 語の一部（pronunciationParts）
		{"ไลฟ์สตรีม", "lái-sà-triim"},
		{"เทศกาลสงกรานต์", "thêet-sà-kaan-sǒng-kraan"},
		{"คลิปนี้", "khlíp-níi"},
		{"มีตติ้ง", "mîit-tîng"},
		{"งานมีตติ้ง", "ngaan-mîit-tîng"},
		{"งานแฟนมีตติ้ง", "ngaan-fɛɛn-mîit-tîng"},
		{"ภรรยา", "phan-rá-yaa"},
		{"ภรรยาของเขา", "phan-rá-yaa-khɔ̌ɔng-khǎw"},
		{"พลาสติก", "phlâat-sà-tìk"},
		{"ถุงพลาสติก", "thǔng-phlâat-sà-tìk"},
		// 他の語の中で読みが変わる綴りは変えない
		{"เขมร", "khà-měen"},
		// 数字
		{"2", "sɔ̌ɔng"},
		{"21", "yîi-sìp-èt"},
		{"5,000", "hâa-phan"},
		{"๒๕", "yîi-sìp-hâa"},
		{"1.5", "nʉ̀ng-jùt-hâa"},
		{"ชั้น2", "chán-sɔ̌ɔng"},
		{"สัก 1 จาน", "sàk nʉ̀ng jaan"},
		// 閉じた音節の ส は変えない
		{"สบอารมณ์", "sòp-aa-rom"},
		{"สด", "sòt"},
	}
	for _, c := range cases {
		got, err := ThaiToPronunciation(c.in)
		if err != nil {
			t.Fatal(err)
		}
		if got != c.want {
			t.Errorf("ThaiToPronunciation(%q) = %q, want %q", c.in, got, c.want)
		}
	}
}
