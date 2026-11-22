// Package ttsaudio はお手本音声（例文の全文を Cloud TTS で読んだ MP3）を作って GCS に置く。
//
// 設計は docs/design_listening_playback.md。要点:
//   - 声は例文の中身だけで決める（文末 → 一人称 → BL → ฉัน → ハッシュ）。ランダムにしない
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

// 文末の丁寧語（女性）。男性の ครับ・คับ は politeGender に直書き。
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
	if chanSpeaker(in.Words) {
		return female
	}
	return unknown
}

// chanSpeaker は一人称 ฉัน（ของฉัน も）があるか。ฉัน は男女とも使うので BL より後に見る。
// コーパス（ja）で ฉัน と丁寧語が両方ある文は女性 716・男性 4（2026-11-22）。
// เรา は女性 115・男性 168 で割れたので見ない。
func chanSpeaker(words []Word) bool {
	for _, w := range words {
		if isPronoun(w) && strings.TrimPrefix(strings.TrimSpace(w.Word), "ของ") == "ฉัน" {
			return true
		}
	}
	return false
}

// endingGender は文末の丁寧語を見る。単語分解があれば最後の語（記号は飛ばす）、
// 無ければ文字列の末尾で見る。
// 最後の語で決まらなければ、単語分解を後ろから見て丁寧語の語を探す
// （ครับอาจารย์・นะครับพี่・ค่ะคุณตั้ม・ครับตอนนี้ のように丁寧語の後ろに呼びかけ等が続く文）。
// コーパス（ja・en）に男女の丁寧語が両方ある文は無かった（2026-11-22）。
func endingGender(text string, words []Word) gender {
	var thaiWords []string
	for _, w := range words {
		if w := strings.TrimSpace(w.Word); hasThai(w) {
			thaiWords = append(thaiWords, w)
		}
	}
	if len(thaiWords) == 0 {
		return politeGender(strings.TrimRightFunc(text, func(r rune) bool { return !isThai(r) }), false)
	}
	for i := len(thaiWords) - 1; i >= 0; i-- {
		if g := politeGender(thaiWords[i], true); g != unknown {
			return g
		}
	}
	return unknown
}

// politeGender は s が丁寧語で終わるか（単語なら ครับผม のように ครับ で始まるものも）を見る。
// คับ は บังคับ と紛れるので、語そのものが คับ のときだけ数える。
// คะ で始まる คะแนน は末尾の一致で見るので当たらない。
func politeGender(s string, isWord bool) gender {
	for _, e := range femaleEnds {
		if strings.HasSuffix(s, e) {
			return female
		}
	}
	if strings.HasSuffix(s, "ครับ") || (isWord && (s == "คับ" || strings.HasPrefix(s, "ครับ"))) {
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
