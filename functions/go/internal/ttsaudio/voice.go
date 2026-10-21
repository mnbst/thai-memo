// Package ttsaudio はお手本音声（例文の全文を Cloud TTS で読んだ MP3）を作って GCS に置く。
//
// 設計は docs/design_listening_playback.md。要点:
//   - 声は例文の中身だけで決める（文末 → 一人称 → BL → ハッシュ）。ランダムにしない
//   - ファイル名は audio/sha256(版|声|速さ|文).mp3。同じ文は誰が要求しても同じファイル
//   - 無いときだけ作る。GCS へは「無いときだけ書く」条件付きで置く
package ttsaudio

import (
	"crypto/sha256"
	"encoding/binary"
	"strings"
	"unicode"
)

// VoiceConfigVersion は声のルール・声の表の版。変えるとファイル名が全部変わり、
// 次に要求されたときに作り直される。ルールか表を変えたときだけ上げる。
const VoiceConfigVersion = "1"

// SpeakingRate は生成時の速さ。ゆっくりは再生側の setSpeed で作る。
const SpeakingRate = "1.0"

// 声の表（Chirp3-HD th-TH）。同じ性別の中はハッシュで選ぶ。
var (
	maleVoices   = []string{"th-TH-Chirp3-HD-Charon", "th-TH-Chirp3-HD-Puck", "th-TH-Chirp3-HD-Orus"}
	femaleVoices = []string{"th-TH-Chirp3-HD-Kore", "th-TH-Chirp3-HD-Aoede", "th-TH-Chirp3-HD-Leda"}
)

// Word は声の判定に使う単語分解の1件（word_breakdown の必要な項目だけ）。
type Word struct {
	Word            string `json:"word"`
	Meaning         string `json:"meaning"`
	GrammaticalRole string `json:"grammatical_role"`
}

// Input は音声を作る例文の中身。
type Input struct {
	ThaiText string `json:"thai_text"`
	// Topic は context.topic。BL ドラマの判定に使う。古い履歴では空。
	Topic string `json:"topic"`
	Words []Word `json:"words"`
}

type gender int

const (
	unknown gender = iota
	male
	female
)

// 文末の丁寧語（女性）。男性の ครับ・คับ は endingGender に直書き。
var femaleEnds = []string{"ค่ะ", "คะ", "คร่ะ"}

// 一人称。ผม（髪）・หนู（ネズミ）と紛れるので、単語分解で代名詞の語に限る。
var (
	malePronouns   = []string{"ผม", "กระผม"}
	femalePronouns = []string{"ดิฉัน", "หนู"}
)

// Normalize は読み上げる文を整える。絵文字を落とし、空白を1つにまとめる。
// ファイル名もこの結果から作るので、空白や絵文字の違いでは別ファイルにならない。
func Normalize(text string) string {
	var b strings.Builder
	for _, r := range text {
		switch {
		case r == '‍' || r == '️' || r == '︎':
			continue
		case unicode.Is(unicode.So, r) || unicode.Is(unicode.Sk, r) || unicode.Is(unicode.Cs, r):
			continue
		case unicode.IsSpace(r):
			b.WriteRune(' ')
		default:
			b.WriteRune(r)
		}
	}
	return strings.Join(strings.Fields(b.String()), " ")
}

// ChooseVoice は例文の中身から Chirp3-HD の声の名前を決める。text は Normalize 済み。
func ChooseVoice(text string, in Input) string {
	sum := sha256.Sum256([]byte(text))
	g := genderOf(text, in)
	if g == unknown {
		if sum[0]%2 == 0 {
			g = male
		} else {
			g = female
		}
	}
	voices := femaleVoices
	if g == male {
		voices = maleVoices
	}
	return voices[binary.BigEndian.Uint32(sum[1:5])%uint32(len(voices))]
}

func genderOf(text string, in Input) gender {
	if g := endingGender(text, in.Words); g != unknown {
		return g
	}
	if g := pronounGender(in.Words); g != unknown {
		return g
	}
	if strings.Contains(in.Topic, "BL") {
		return male
	}
	return unknown
}

// endingGender は文末の丁寧語を見る。単語分解があれば最後の語（記号は飛ばす）、
// 無ければ文字列の末尾で見る。คับ は語そのものが คับ のときだけ数える。
func endingGender(text string, words []Word) gender {
	tail, isWord := strings.TrimRightFunc(text, func(r rune) bool { return !isThai(r) }), false
	for i := len(words) - 1; i >= 0; i-- {
		if w := strings.TrimSpace(words[i].Word); hasThai(w) {
			tail, isWord = w, true
			break
		}
	}
	for _, e := range femaleEnds {
		if strings.HasSuffix(tail, e) {
			return female
		}
	}
	if strings.HasSuffix(tail, "ครับ") || (isWord && tail == "คับ") {
		return male
	}
	return unknown
}

func pronounGender(words []Word) gender {
	for _, w := range words {
		if !isPronoun(w) {
			continue
		}
		if g := matchWord(strings.TrimSpace(w.Word), malePronouns, femalePronouns); g != unknown {
			return g
		}
	}
	return unknown
}

func isPronoun(w Word) bool {
	role := strings.ToLower(w.GrammaticalRole)
	if strings.Contains(role, "代名詞") || strings.Contains(role, "pronoun") {
		return true
	}
	return strings.Contains(w.Meaning, "私")
}

func matchWord(w string, m, f []string) gender {
	for _, s := range m {
		if w == s {
			return male
		}
	}
	for _, s := range f {
		if w == s {
			return female
		}
	}
	return unknown
}

func isThai(r rune) bool { return r >= 0x0E00 && r <= 0x0E7F }

func hasThai(s string) bool {
	for _, r := range s {
		if isThai(r) {
			return true
		}
	}
	return false
}
