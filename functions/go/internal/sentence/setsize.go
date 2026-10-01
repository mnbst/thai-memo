package sentence

// 入門者のセットの本数。
//
// ヒアリングで「まったく初めて」と答えた層は、1セット5本の途中で離れやすい
// （2026-10 prod: まとめクイズ到達 26%、7日後も利用 10%。他の層は 47〜69% / 22〜30%）。
// 1サイクルを短くして早くまとめクイズまで届かせ、語彙スコアが伸びるにつれて
// SetSize へ近づける。まとめクイズ1回で語彙スコアはおよそ +8 なので、
// 0→50 はまとめクイズ8〜10回ぶん。
const (
	// BeginnerMinSetSize は入門者の最初のセットの本数。1本だとまとめクイズが
	// 出ない（クライアントの isLast は2本以上）ので2が下限。
	BeginnerMinSetSize = 2

	// BeginnerRampVocab はこの語彙スコアに届いたら SetSize に戻す境目。
	BeginnerRampVocab = 50
)

// beginnerStartSizes はヒアリング（interview.level）ごとの最初のセットの本数。
// 載っていない回答（chars / conv / 未回答）は最初から SetSize。
//
// 最初の5本セットの消化（2026-10 prod）で決めた。none は5本読了 40%・平均 2.8本、
// words は 50%・3.4本で途中で止まる。chars は 9人全員が読み切っていて縮めない。
var beginnerStartSizes = map[string]int{
	"none":  BeginnerMinSetSize, // まったく初めて
	"words": 3,                  // 単語や挨拶はわかる
}

// SetSizeFor はそのユーザーの1セットの本数。例文生成・毎日配信・まとめクイズの
// 問題数はすべてこれにそろえる。
//
// 入門者は beginnerStartSizes の本数から始め、語彙スコア BeginnerRampVocab で
// SetSize に届くよう等間隔に増やす。
//   - none:  0〜16 → 2本、17〜33 → 3本、34〜49 → 4本、50以上 → SetSize
//   - words: 0〜24 → 3本、25〜49 → 4本、50以上 → SetSize
//
// それ以外は SetSize。
func SetSizeFor(userData map[string]any) int {
	interview, _ := userData["interview"].(map[string]any)
	level, _ := interview["level"].(string)
	start, ok := beginnerStartSizes[level]
	if !ok {
		return SetSize
	}
	vocab := max(numberToInt(userData["estimated_vocab"]), 0)
	if vocab >= BeginnerRampVocab {
		return SetSize
	}
	return start + vocab*(SetSize-start)/BeginnerRampVocab
}

// numberToInt は Firestore が返す数値（int64 / float64）を int にする。
func numberToInt(v any) int {
	switch n := v.(type) {
	case int64:
		return int(n)
	case int:
		return n
	case float64:
		return int(n)
	}
	return 0
}
