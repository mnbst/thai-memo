package quality

import (
	"regexp"
	"strings"

	"github.com/mnbst/thai-memo/functions/go/internal/lang"
)

// コードで判定する訳の観点（Aspect.Check）。Jev に聞かず、正規表現と語の表で決める。
//
// 足してよいのは、形で確実に決まり誤検出が出ないものだけ。2026-09-30 に
// 次のデータで測った（英訳は目視ラベル付きの 363 文、日本語訳は 568 文）:
//
//	gramTerm       英訳 5 件・誤検出 0
//	bareNot        英訳 6 件・誤検出 0（主語の直前が助動詞の疑問文は除く）
//	knownMistrans  日本語訳 10 件・誤検出 0
//
// 見送ったもの:
//   - 英訳の語の羅列を広く拾う正規表現（文末の very/already、want＋原形 等）は
//     再現率 25/80・誤検出 15/160 で使えない
//   - 訳にだけ接続語（ので／から／けど）がある文は 45 件当たったが、大半は
//     節の並置を自然に訳したもので誤りではない

// gramTermRe は訳に書かれた品詞名・文法用語と角括弧。語の並びは静的コーパスの
// 英訳チェック（corpustrans.reGrammarTerm）に合わせてある。quality から corpustrans を
// import すると sentence 以下まで引き込むので写している。片方を直したらもう片方も直す。
var gramTermRe = regexp.MustCompile(
	`\[|\]|(?i)\b(particles?|classifiers?|progressive|emphatic|aspect marker|polite ending|sentence[- ]final)\b`)

// gramTerm は訳に品詞名・文法用語・角括弧が残っているか。
func gramTerm(c Candidate) bool {
	return gramTermRe.MatchString(c.JapaneseTranslation)
}

// bareNotRe は「主語＋not」。直前の語は助動詞かどうかの判定に使う。
var bareNotRe = regexp.MustCompile(`(?i)(?:(\w+)\s+)?\b(I|you|we|they|he|she|it)\s+not\b`)

// notAux は「Do you not 〜」のように主語の前に置いて not を正しく使える語。
var notAux = map[string]bool{
	"do": true, "does": true, "did": true, "will": true, "would": true,
	"can": true, "could": true, "should": true, "must": true,
	"am": true, "is": true, "are": true, "was": true, "were": true,
	"have": true, "has": true, "had": true,
}

// bareNot は英訳が否定を助動詞なしの not で表しているか（×I not go）。
func bareNot(c Candidate) bool {
	if c.Lang != lang.EN {
		return false
	}
	for _, m := range bareNotRe.FindAllStringSubmatch(c.JapaneseTranslation, -1) {
		if !notAux[strings.ToLower(m[1])] {
			return true
		}
	}
	return false
}

// mistrans は語の範囲を狭めて訳す既知の誤訳 1 件。
type mistrans struct {
	// Word が thai_text にあり、Unless のどれも無いときに判定する。
	Word   string
	Unless []string
	// Bad は訳に出たら誤訳とする訳語（言語ごと）。
	Bad map[lang.Lang]*regexp.Regexp
}

// knownMistranslations は prod で繰り返し出た誤訳。
var knownMistranslations = []mistrans{
	// ตลาดนัด は日を決めて立つ市。夜に限らない（prod プール ja 232件中4件、罠で3件）。
	{Word: "ตลาดนัด",
		Unless: []string{"กลางคืน", "คืนนี้", "ตอนค่ำ", "ตอนเย็น", "เย็นนี้"},
		Bad: map[lang.Lang]*regexp.Regexp{
			lang.JA: regexp.MustCompile(`ナイト|夜市|フリーマーケット|フリマ`),
			lang.EN: regexp.MustCompile(`(?i)night market|flea market`),
		}},
	// รถไฟฟ้า は電車一般。路線名にしない（prompt-effect-ledger「2段構成」）。
	{Word: "รถไฟฟ้า",
		Unless: []string{"บีทีเอส", "BTS", "เอ็มอาร์ที", "MRT"},
		Bad: map[lang.Lang]*regexp.Regexp{
			lang.JA: regexp.MustCompile(`BTS|MRT`),
			lang.EN: regexp.MustCompile(`BTS|MRT`),
		}},
}

// knownMistrans は knownMistranslations のどれかに当たるか。
func knownMistrans(c Candidate) bool {
	l := c.Lang
	if l == "" {
		l = lang.JA
	}
	for _, m := range knownMistranslations {
		if !strings.Contains(c.ThaiText, m.Word) {
			continue
		}
		skip := false
		for _, u := range m.Unless {
			if strings.Contains(c.ThaiText, u) {
				skip = true
				break
			}
		}
		if bad := m.Bad[l]; !skip && bad != nil && bad.MatchString(c.JapaneseTranslation) {
			return true
		}
	}
	return false
}

// wordMisuseRe は、日本語訳が当てはまるだけで場面の違う語を当てた既知の形
// （prod プール監査 2026-09-30）。静的コーパス 15,864 文で当たるのは 0 件。
//
//	สบายดี  体調の「元気」を物や場所の感想に使う（×ใส่แล้วสบายดี／×อากาศที่นี่สบายดี）。
//	        食後の体調を聞く ○กินกุ้งแล้วสบายดีไหม は正しいので疑問形は外す。
//	        ○คุณคงสบายดี（人の近況の推量）も正しいので คง は見ない
//	ยอด     山頂・金額の「頂」を物や体の上端に使う（×ยอดชั้น／×ยอดไหล่）
//	บางที   「もしかして」の直訳で依頼の前置きにする（×บางทีคุณลดราคาให้ได้ไหม）
//	วิน     乗り場・サービスの名を乗り物そのものにする（×อย่าขยับบนวิน）
var wordMisuseRe = []*regexp.Regexp{
	regexp.MustCompile(`(ใส่|กิน|ทาน|ใช้|นั่ง|นอน)\S{0,24}?แล้วสบายดี|อากาศ\S{0,8}?สบายดี`),
	regexp.MustCompile(`ยอด(ชั้น|ไหล่|นิ้ว|ตู้|โต๊ะ|หัว|บันได)|จุดยอด`),
	regexp.MustCompile(`บางที.*(ได้ไหม|ได้มั้ย|ได้หรือเปล่า|ให้หน่อย)`),
	regexp.MustCompile(`บนวิน`),
}

// sabaideeQuestionRe は สบายดี の直後に疑問の語が続く形（体調を聞く正しい用法）。
var sabaideeQuestionRe = regexp.MustCompile(`สบายดี(ไหม|มั้ย|หรือ)`)

// wordMisuse は thai_text に wordMisuseRe の形があるか。
func wordMisuse(c Candidate) bool {
	t := sabaideeQuestionRe.ReplaceAllString(c.ThaiText, "")
	for _, re := range wordMisuseRe {
		if re.MatchString(t) {
			return true
		}
	}
	return false
}

// wordUsage は、語が文にあるときだけ Jev に用法を聞く観点 1 つ。
//
// 語の検出はコード、用法の正誤は Jev が受け持つ。汎用の key_word の観点
// （「本来と違う意味で使われているか」）は語の範疇を指さないので拾えない。
// 2026-09-30、4語を含む 203 文（誤用 61、目視ラベル、2回で差 ≤0.08）:
//
//	語       語ごとの問い（閾値）  汎用の問い（0.4）
//	สบายดี   16/18・誤検出 0/38    3/18・0/38
//	ยอด      21/23・誤検出 3/20    6/23・0/20
//	บางที    8/9・誤検出 0/38      0/9・0/38
//	วิน      10/11・誤検出 3/46    1/11・1/46
//
// ยอด の誤検出は ยอดนักกีฬา／ถึงยอด／ยอดราชรถ、วิน は運転手とも人名とも読める
// พี่วิน。ラベルは単独判定で、閾値も同じデータで選んでいる。
type wordUsage struct {
	ID   string
	Word string
	// Skip は Word を含むが別の語になる綴り（วินาที 等）。取り除いてから Word を探す。
	Skip      []string
	Question  string
	Note      string
	Threshold float64
}

var wordUsages = []wordUsage{
	{ID: "usage_sabaidee", Word: "สบายดี", Threshold: 0.3,
		Question: "`thai_text` の สบายดี が、人の体調・近況（元気かどうか）以外の意味（物・場所・料理・天気・移動が快適、心地よい 等）で使われているか",
		Note:     "thai_text で、体調・近況を言う語を、物・場所・料理・天気・移動の心地よさに使っていた。その語は人が元気かどうかを言うときだけ使う"},
	{ID: "usage_yod", Word: "ยอด", Threshold: 0.3,
		Question: "`thai_text` の ยอด が、山・塔・木などの頂上、植物の若芽、金額や件数の合計、複合語（ยอดเยี่ยม、สุดยอด 等）以外の意味（物や体の上端・先端、順位の一番、ピーク 等）で使われているか",
		Note:     "thai_text で、頂上・合計を表す語を、物や体の上端・先端、一番、ピークの意味に使っていた。その意味は別の語で言う"},
	{ID: "usage_bangthi", Word: "บางที", Threshold: 0.6,
		Question: "`thai_text` の บางที が「時々」または推量の「もしかすると」以外の使い方、特に依頼・誘い・提案の前置き（〜してもらえますか、〜しよう、〜しない？）として使われているか",
		Note:     "thai_text で、「時々／もしかすると」を表す語を依頼・誘い・提案の前置きに使っていた。依頼や誘いには使わない"},
	{ID: "usage_win", Word: "วิน", Threshold: 0.5,
		Skip:     []string{"วินาที", "วินัย", "วินาศ", "วินิจฉัย"},
		Question: "`thai_text` の วิน が、バイクタクシー（乗り場・運転手・サービス）の意味以外（人名、秒の略、乗り物そのもの 等）で使われているか",
		Note:     "thai_text で、バイクタクシーの乗り場・運転手を表す語を、人名・秒の略・乗り物そのものに使っていた。バイクタクシーの意味で使う"},
}

// has は t に Word があるか（Skip の綴りは除く）。
func (u wordUsage) has(t string) bool {
	for _, s := range u.Skip {
		t = strings.ReplaceAll(t, s, "")
	}
	return strings.Contains(t, u.Word)
}

// wordUsageAspects は wordUsages を観点にする。
func wordUsageAspects() []Aspect {
	out := make([]Aspect, len(wordUsages))
	for i, u := range wordUsages {
		out[i] = Aspect{
			ID: u.ID, Label: "語の用法", Question: u.Question, Note: u.Note, Threshold: u.Threshold,
			Trigger: func(c Candidate) bool { return u.has(c.ThaiText) },
		}
	}
	return out
}

// kotamFollowRe は ก็＋ตาม（ついて行く・従う）で譲歩ではない形（ก็ตามใจ／ก็ตามมา 等）。
var kotamFollowRe = regexp.MustCompile(`ก็ตาม(ใจ|นั้น|นี้|หา|ไป|มา|ด้วย|กัน|ทัน)`)

// kotamHeadRe は ก็ตาม と組む譲歩の頭（ถึง／แม้／ไม่ว่า／ต่อให้／疑問詞／〜หรือไม่）。
var kotamHeadRe = regexp.MustCompile(`ถึง|แม้|ไม่ว่า|ต่อให้|ไหน|อะไร|ใคร|ยังไง|อย่างไร|เท่าไ|หรือไม่|หรือเปล่า|เมื่อไ`)

// concessiveNoHead は ก็ตาม を譲歩の頭なしで置いているか（×พรุ่งนี้ทัวร์จะเลื่อนก็ตาม）。
// จะ だけでは頭にならない。頭は同じ空白区切りの節の中、ก็ตาม より前を探す。
//
// 2026-09-30、ก็ตาม を含む 75 文（罠・prod プール・静的コーパス 21 文）で
// 当たるのは頭なしの 4 文だけ。頭はあるのに譲歩と主節が対立しない文
// （×ถึงแม้เพิ่งเคยเห็นผีตัวนี้ กูยังตกใจไม่หาย）は Jev でも分離できず見送った
// （譲歩構文を名指す問いで 6 件中 0〜2 件、誤検出 1〜12/149）。
func concessiveNoHead(c Candidate) bool {
	for _, seg := range strings.Fields(kotamFollowRe.ReplaceAllString(c.ThaiText, "")) {
		for _, part := range strings.Split(seg, "ก็ตาม")[:strings.Count(seg, "ก็ตาม")] {
			if !kotamHeadRe.MatchString(part) {
				return true
			}
		}
	}
	return false
}
