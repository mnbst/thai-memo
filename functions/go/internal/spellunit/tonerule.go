package spellunit

// 声調が決まる3つの要素。
//
// タイ語の声調は「頭子音の階級 × 音節の型（生音/死音）× 声調記号」で
// 決まる。綴り4択の答え合わせで、声調の欄にこの3つを出して、
// 声調を暗記ではなく規則として読ませる。

// ToneRule は声調を決める3要素。
type ToneRule struct {
	// Class は頭子音の階級。mid / high / low。
	Class string `json:"class"`
	// Syllable は音節の型。live（生音）/ dead（死音）。
	Syllable string `json:"syllable"`
	// Mark は声調記号。無記号は空。
	Mark string `json:"mark,omitempty"`
	// ShortVowel は短母音か。低子音の死音は母音の長短で声調が変わるので、
	// 表のどの行かを決めるのに要る。
	ShortVowel bool `json:"short_vowel,omitempty"`
}

// 階級は綴りの頭の子音字で決まる。ห นำ（หน・หม…）や อย は前に置いた
// 字の階級が効くので、頭子音のかたまりの**最初の**子音字を見る。
var midConsonants = "กจฎฏดตบปอ"
var highConsonants = "ขฃฉฐถผฝศษสห"

// shortVowels は短母音のコード。長母音は重ねて書く（aa, ii…）。
var shortVowels = map[string]bool{
	"a": true, "i": true, "u": true, "e": true, "e-": true,
	"o": true, "O": true, "x": true, "U": true, "ia": true,
}

// deadCodas は音を止める末子音（破裂音）。これで終わると死音。
var deadCodas = map[string]bool{"k": true, "p": true, "t": true}

// ToneRule は綴りから声調の3要素を出す。
// 綴りを切り分けられない語では ok=false（階級を読む字が決まらない）。
func (ix *Index) ToneRule(word string) (ToneRule, bool) {
	code, ok := ix.Lookup(word)
	if !ok {
		return ToneRule{}, false
	}
	texts, ok := segment(word, code)
	if !ok {
		return ToneRule{}, false
	}

	rule := ToneRule{
		Mark:       texts[DimTone],
		Syllable:   "live",
		ShortVowel: shortVowels[code.Vowel],
	}
	for _, ch := range texts[DimOnset] {
		if !isConsonant(ch) {
			continue
		}
		switch {
		case containsRune(midConsonants, ch):
			rule.Class = "mid"
		case containsRune(highConsonants, ch):
			rule.Class = "high"
		default:
			rule.Class = "low"
		}
		break
	}
	if rule.Class == "" {
		return ToneRule{}, false
	}

	// 死音は「破裂音で終わる」か「末子音が無くて短母音」。
	if deadCodas[code.Coda] || (code.Coda == "" && shortVowels[code.Vowel]) {
		rule.Syllable = "dead"
	}
	return rule, true
}

func containsRune(set string, ch rune) bool {
	for _, r := range set {
		if r == ch {
			return true
		}
	}
	return false
}
