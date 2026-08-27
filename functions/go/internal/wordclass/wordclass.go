// Package wordclass は key_word の語クラス辞書。
// functions/python/word_classes.py の移植。
//
// 分類とルール文はすべてデータ側（classes_data.go、word_classes.json 由来）に
// 置き、ここはロードと逆引きだけを持つ。
// ルールを増やすときは word_classes.json にクラスを足して再生成する。
package wordclass

// Class は1つの語クラス。
type Class struct {
	// Label は【ターゲット語は〇〇】の見出しに使う。
	Label string
	// FunctionWord が true なら機能語。プロンプトに FUNCTION_WORD_STEPS を足す。
	FunctionWord bool
	// Rule はクラス固有の指示。空なら付けない。
	Rule  string
	Words []string
}

// wordToClass は単語 → クラスID。
// 同じ語が複数クラスに現れた場合は先に定義したクラスを採用する
// （Python の dict.setdefault と同じ）。
var wordToClass = func() map[string]string {
	out := map[string]string{}
	for _, cid := range classOrder {
		for _, w := range classes[cid].Words {
			if _, exists := out[w]; !exists {
				out[w] = cid
			}
		}
	}
	return out
}()

// Classify は語のクラスIDを返す。未分類（内容語）なら空文字。
func Classify(word string) string {
	return wordToClass[word]
}

// ClassifyAll はターゲット語のクラスIDを、重複を除いて出現順に返す。
func ClassifyAll(words []string) []string {
	var seen []string
	inSeen := map[string]bool{}
	for _, w := range words {
		cid := Classify(w)
		if cid == "" || inSeen[cid] {
			continue
		}
		inSeen[cid] = true
		seen = append(seen, cid)
	}
	return seen
}

// IsFunctionWord は機能語かどうか。
func IsFunctionWord(word string) bool {
	cid := Classify(word)
	return cid != "" && classes[cid].FunctionWord
}

// Get はクラスIDから定義を引く。
func Get(cid string) (Class, bool) {
	c, ok := classes[cid]
	return c, ok
}

// AllWords は辞書に載っている全ての語（差分テスト用）。
func AllWords() []string {
	out := make([]string, 0, len(wordToClass))
	for _, cid := range classOrder {
		out = append(out, classes[cid].Words...)
	}
	return out
}
