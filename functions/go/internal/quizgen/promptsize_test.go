package quizgen

import (
	"strings"
	"testing"

	"github.com/mnbst/thai-memo/functions/go/internal/lang"
)

// ダミーを確定させたぶん、指示から落とせた量を記録する。
//
// 落としたのは「どの語をダミーにしてよいか」の条件（【ダミー条件】【NG例】
// 訳文だけで区別する語の禁止）。選定がコード側へ移ったので、守らせる相手が
// いない。残したのは dummy_reasons の書式と、訳文なしで解けることの確認。
func TestFixedDummyPromptIsShorter(t *testing.T) {
	for _, l := range []lang.Lang{lang.JA, lang.EN} {
		old := []rune(SystemPrompt(l))
		fixed := []rune(fixedDummyPrompt(l))
		t.Logf("%s: 従来 %d文字 → ダミー確定 %d文字（%.0f%%減）",
			l, len(old), len(fixed), 100*(1-float64(len(fixed))/float64(len(old))))
		if len(fixed) >= len(old) {
			t.Errorf("%s: 短くなっていない", l)
		}
	}
}

// 書式に関わる指示は落とさない。dummy_reasons の「語（ローマ字 / 意味）：理由」は
// extractDummyPronunciation が依存していて、崩すと4択の発音表示が空になる。
func TestFixedDummyPromptKeepsReasonFormat(t *testing.T) {
	for _, l := range []lang.Lang{lang.JA, lang.EN} {
		p := fixedDummyPrompt(l)
		if !strings.Contains(p, dummyReasonFormat[l]) {
			t.Errorf("%s: dummy_reasons の書式が落ちている", l)
		}
		if !strings.Contains(p, visibilityRule[l]) {
			t.Errorf("%s: 訳文なしで解ける制約が落ちている", l)
		}
	}
}
