package function

import (
	"os"
	"sort"
	"testing"

	"github.com/mnbst/thai-memo/functions/go/internal/thainlp"
)

// TestCorpusPOSVsTaggerLive は辞書（文中で付いた品詞）と単体タグ付けの
// 食い違いを数える。辞書を先に引く価値がどれだけあるかの実測。
//
//	QUIZ_DISTRACTOR_LIVE=1 go test ./ -run TestCorpusPOSVsTaggerLive -v
func TestCorpusPOSVsTaggerLive(t *testing.T) {
	if os.Getenv("QUIZ_DISTRACTOR_LIVE") == "" {
		t.Skip("QUIZ_DISTRACTOR_LIVE=1 で実行する")
	}
	words := make([]string, 0, len(corpusPOS))
	for w := range corpusPOS {
		words = append(words, w)
	}
	sort.Strings(words)
	if len(words) > 800 {
		words = words[:800]
	}

	var same, diff, failed int
	examples := make([]string, 0, 10)
	for _, w := range words {
		tag, err := thainlp.POSJapanese(w)
		if err != nil {
			failed++
			continue
		}
		if tag == corpusPOS[w] {
			same++
			continue
		}
		diff++
		if len(examples) < 10 {
			examples = append(examples, w+" 辞書="+corpusPOS[w]+" 単体="+tag)
		}
	}
	t.Logf("一致 %d / 食い違い %d / 失敗 %d（%d語）", same, diff, failed, len(words))
	for _, e := range examples {
		t.Logf("  %s", e)
	}
}
