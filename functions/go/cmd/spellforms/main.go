// spellforms はアプリ同梱の綴り対応表（assets/spelling_forms.json）を書き出す。
//
// 綴り4択の対応表（spellunit）にある綴りはその読みを使い、無い音節は G2P で読む。
// sylform_var は音節形ごとの見本なので、ความ・จะ のような基本の音節も欠けている。
//
//	cd functions/go && go run ./cmd/spellforms
package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"log"
	"os"
	"regexp"
	"sort"
	"strings"

	"github.com/mnbst/thai-memo/functions/go/internal/spellunit"
	"github.com/mnbst/thai-memo/functions/go/internal/thainlp"
)

const (
	syllablesPath = "internal/thainlp/data/syllables_th.txt"
	freqRankPath  = "../../scripts/corpus/freq_rank.json"
	outputPath    = "../../assets/spelling_forms.json"
)

func main() {
	candidates, err := collectCandidates()
	if err != nil {
		log.Fatal(err)
	}
	ix, err := spellunit.LoadIndex()
	if err != nil {
		log.Fatal(err)
	}

	forms := map[string][]string{}
	for form := range candidates {
		code := ""
		if known, ok := ix.Lookup(form); ok && !strings.Contains(known.String(), "~") {
			code = known.String()
		} else {
			code = g2pCode(form)
		}
		if code != "" {
			forms[code] = append(forms[code], form)
		}
	}
	total := 0
	for _, list := range forms {
		sort.Strings(list)
		total += len(list)
	}

	var buf bytes.Buffer
	enc := json.NewEncoder(&buf)
	enc.SetEscapeHTML(false)
	if err := enc.Encode(forms); err != nil {
		log.Fatal(err)
	}
	if err := os.WriteFile(outputPath, bytes.TrimSpace(buf.Bytes()), 0o644); err != nil {
		log.Fatal(err)
	}
	fmt.Printf("%s: %d codes, %d forms\n", outputPath, len(forms), total)
}

// collectCandidates は表に載せる綴りの候補を集める。
func collectCandidates() (map[string]bool, error) {
	out := map[string]bool{}

	data, err := thainlp.Load()
	if err != nil {
		return nil, err
	}
	for _, raw := range data.SylVar {
		list, ok := raw.([]any)
		if !ok {
			continue
		}
		for _, form := range list {
			if s, ok := form.(string); ok && s != "" {
				out[s] = true
			}
		}
	}

	raw, err := os.ReadFile(syllablesPath)
	if err != nil {
		return nil, err
	}
	for _, line := range strings.Split(string(raw), "\n") {
		if s := strings.TrimSpace(line); s != "" {
			out[s] = true
		}
	}

	// アプリの語はこの分割で音節に切られるので、辞書に無い単位も拾う。
	raw, err = os.ReadFile(freqRankPath)
	if err != nil {
		return nil, err
	}
	var freq map[string]any
	if err := json.Unmarshal(raw, &freq); err != nil {
		return nil, err
	}
	for word := range freq {
		syllables, err := thainlp.SegmentSyllables(word)
		if err != nil {
			continue
		}
		for _, s := range syllables {
			out[s] = true
		}
	}
	return out, nil
}

// shortSchwa は G2P が短い ə を表す @（長い @@ は別）。音節形コードでは e-。
var shortSchwa = regexp.MustCompile(`@+`)

func normalizeCode(code string) string {
	return shortSchwa.ReplaceAllStringFunc(code, func(m string) string {
		if m == "@" {
			return "e-"
		}
		return m
	})
}

// g2pCode は綴りの音節形コードを返す。扱えない綴りは空。
//
// 返すのは単音節のコードと、ตลาด（ta1'laat1）・บริ（bOO0'ri3）のように
// 先頭の子音字だけで母音を読む2音のコード。
func g2pCode(form string) string {
	out, err := thainlp.G2P(form)
	if err != nil {
		return ""
	}
	_, rest, ok := strings.Cut(out, "<tr/>")
	if !ok {
		return ""
	}
	raw, tail, ok := strings.Cut(rest, "|")
	if !ok || tail != "<s/>" {
		return ""
	}
	code := normalizeCode(raw)
	// ~ は発音の区切り（อ.ส. = ?OO0~sOO4）で、1音節のコードではない。
	if strings.Contains(code, "~") {
		return ""
	}
	if _, ok := spellunit.ParseCode(code); ok {
		return code
	}
	first, second, ok := strings.Cut(code, "'")
	if !ok || !splitsAfterFirstRune(form) {
		return ""
	}
	head, ok := spellunit.ParseCode(first)
	if !ok || (head.Vowel != "a" && head.Vowel != "OO") || head.Coda != "" {
		return ""
	}
	if _, ok := spellunit.ParseCode(second); !ok {
		return ""
	}
	return code
}

// splitsAfterFirstRune は先頭の子音字1つと残りに分けられる綴りか。
func splitsAfterFirstRune(form string) bool {
	r := []rune(form)
	if len(r) < 2 || !isThaiConsonant(r[0]) {
		return false
	}
	return isThaiConsonant(r[1]) || strings.ContainsRune("เแโใไ", r[1])
}

func isThaiConsonant(r rune) bool { return r >= 0x0E01 && r <= 0x0E2E }
