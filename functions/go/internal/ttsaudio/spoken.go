package ttsaudio

import "strings"

const (
	maiYamok   = "ๆ"
	paiyannoi  = "ฯ"
	etcetera   = "ฯลฯ"
	etcPlaceho = "\x00"
)

// SpokenText は Cloud TTS に渡す文。表記どおりに読ませるため、記号を先に展開する。
//   - ๆ は直前の1語だけを繰り返す（TTS は ตรงข้างๆ を「ตรงข้าง ตรงข้าง」と読むことがある）。
//     直前の語は単語分解から取る。分解が無い・合わないときはそのまま渡す
//   - 略記の ฯ は落とす（กรุงเทพฯ を กรุงเทพมหานคร と読ませない）。ฯลฯ は残す
//
// text は Normalize 済み。展開が要らない文は text をそのまま返すので、ファイル名も変わらない。
func SpokenText(text string, words []Word) string {
	if !strings.Contains(text, maiYamok) && !strings.Contains(text, paiyannoi) {
		return text
	}
	s := strings.ReplaceAll(text, etcetera, etcPlaceho)
	s = strings.ReplaceAll(s, paiyannoi, "")
	s = expandMaiYamok(s, words)
	s = strings.ReplaceAll(s, etcPlaceho, etcetera)
	return strings.Join(strings.Fields(s), " ")
}

func expandMaiYamok(s string, words []Word) string {
	var b strings.Builder
	for {
		i := strings.Index(s, maiYamok)
		if i < 0 {
			b.WriteString(s)
			return b.String()
		}
		before := s[:i]
		b.WriteString(before)
		prev := b.String()
		if w := repeatedWord(strings.TrimRight(prev, " "), words); w != "" {
			b.WriteString(w)
		} else {
			b.WriteString(maiYamok)
		}
		s = s[i+len(maiYamok):]
	}
}

// repeatedWord は ๆ の直前にある語。ๆ を含む語（ข้างๆ）を優先し、その中で長いものを選ぶ。
func repeatedWord(prev string, words []Word) string {
	best, bestHad := "", false
	for _, w := range words {
		had := strings.Contains(w.Word, maiYamok)
		base := strings.TrimSpace(strings.ReplaceAll(strings.ReplaceAll(w.Word, maiYamok, ""), paiyannoi, ""))
		if base == "" || !strings.HasSuffix(prev, base) {
			continue
		}
		if (had && !bestHad) || (had == bestHad && len(base) > len(best)) {
			best, bestHad = base, had
		}
	}
	return best
}
