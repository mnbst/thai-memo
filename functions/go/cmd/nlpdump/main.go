// Command nlpdump は差分テストハーネスの Go 側。
//
// corpus.jsonl を読み、Python の gen_golden.py と同じ {tier, api, in, out} の
// JSONL を stdout に吐く。verify.py がこれを golden と突き合わせる。
//
//	go run ./cmd/nlpdump --corpus ../python/scripts/nlp_golden/data/corpus.jsonl > candidate.jsonl
//	../python/.venv/bin/python ../python/scripts/nlp_golden/verify.py \
//	  --golden ../python/scripts/nlp_golden/data/golden.jsonl --candidate candidate.jsonl
//
// 未移植の API は行を出力しない。verify.py が「欠落」として検出するので、
// 空実装が誤って一致扱いされることはない。
package main

import (
	"bufio"
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"sort"
	"strings"

	"github.com/mnbst/thai-memo/functions/go/internal/thainlp"
)

type entry struct {
	Kind string `json:"kind"`
	Text string `json:"text"`
}

type row struct {
	API  string `json:"api"`
	In   string `json:"in"`
	Out  any    `json:"out"`
	Tier int    `json:"tier"`
}

// errorSentinel は Python 側 gen_golden.py の ERROR_SENTINEL と同じ。
// 「現行実装が例外を投げた」ことだけを表し、メッセージは比較しない。
var errorSentinel = map[string]bool{"__error__": true}

// apiCase は gen_golden.py の CASES と1対1に対応する。
type apiCase struct {
	tier  int
	api   string
	kinds map[string]bool
	// fn は出力値を返す。ErrNotImplemented なら行を出さない。
	// それ以外のエラーは errorSentinel を出す。
	fn func(string) (any, error)
}

func wordOnly() map[string]bool     { return map[string]bool{"word": true} }
func sentenceOnly() map[string]bool { return map[string]bool{"sentence": true} }
func both() map[string]bool         { return map[string]bool{"word": true, "sentence": true} }
func wordseqOnly() map[string]bool  { return map[string]bool{"wordseq": true} }

// wordseqSep は extract_corpus.WORDSEQ_SEP と同じ。
const wordseqSep = "\u241f"

func splitSeq(s string) []string {
	var out []string
	for _, w := range strings.Split(s, wordseqSep) {
		if w != "" {
			out = append(out, w)
		}
	}
	return out
}

func cases() []apiCase {
	str := func(f func(string) (string, error)) func(string) (any, error) {
		return func(s string) (any, error) { v, err := f(s); return v, err }
	}
	slice := func(f func(string) ([]string, error)) func(string) (any, error) {
		return func(s string) (any, error) { v, err := f(s); return v, err }
	}
	return []apiCase{
		{1, "thai_to_pronunciation", both(), str(thainlp.ThaiToPronunciation)},
		{1, "segment_syllables", wordOnly(), slice(thainlp.SegmentSyllables)},
		{1, "get_pos_japanese", wordOnly(), str(thainlp.POSJapanese)},
		{1, "tokenize_words", sentenceOnly(), slice(thainlp.TokenizeWords)},
		// gen_golden.py の _th2ipa は .strip() してから記録する。
		// 実装ではなく probe の定義に合わせる必要がある。
		{2, "th2ipa", both(), func(t string) (any, error) {
			v, err := thainlp.TH2IPA(t)
			return strings.TrimSpace(v), err
		}},
		{2, "sylparse", wordOnly(), str(thainlp.SylParse)},
		{2, "wordparse", wordOnly(), str(thainlp.WordParse)},
		{2, "subword_tokenize", wordOnly(), slice(thainlp.SubwordTokenize)},
		{2, "pos_tag_unigram_tud", wordOnly(), func(s string) (any, error) {
			return thainlp.POSTag(s, "tud")
		}},
		{2, "pos_tag_perceptron_orchid_ud", wordOnly(), func(s string) (any, error) {
			return thainlp.POSTag(s, "orchid_ud")
		}},
		{2, "pos_tag_seq_perceptron_orchid_ud", wordseqOnly(), func(s string) (any, error) {
			return thainlp.POSTagSeq(splitSeq(s), "orchid_ud")
		}},
		{2, "pos_tag_seq_unigram_tud", wordseqOnly(), func(s string) (any, error) {
			return thainlp.POSTagSeq(splitSeq(s), "tud")
		}},
	}
}

func main() {
	corpusPath := flag.String("corpus", "", "corpus.jsonl のパス")
	flag.Parse()
	if *corpusPath == "" {
		fmt.Fprintln(os.Stderr, "--corpus は必須")
		os.Exit(2)
	}

	corpus, err := readCorpus(*corpusPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "corpus 読み込み: %v\n", err)
		os.Exit(1)
	}

	if _, err := thainlp.Load(); err != nil {
		fmt.Fprintf(os.Stderr, "データ読み込み: %v\n", err)
		os.Exit(1)
	}

	var rows []row
	skipped := map[string]int{}
	for _, c := range cases() {
		for _, e := range corpus {
			if !c.kinds[e.Kind] {
				continue
			}
			out, err := c.fn(e.Text)
			switch {
			case err == thainlp.ErrNotImplemented:
				skipped[c.api]++
				continue
			case err != nil:
				out = errorSentinel
			}
			rows = append(rows, row{API: c.api, In: e.Text, Out: out, Tier: c.tier})
		}
	}

	// golden と同じ順序に揃える（差分を読みやすくするため）。
	sort.Slice(rows, func(i, j int) bool {
		if rows[i].API != rows[j].API {
			return rows[i].API < rows[j].API
		}
		return rows[i].In < rows[j].In
	})

	w := bufio.NewWriter(os.Stdout)
	defer w.Flush()
	enc := json.NewEncoder(w)
	enc.SetEscapeHTML(false)
	for _, r := range rows {
		if err := enc.Encode(r); err != nil {
			fmt.Fprintf(os.Stderr, "書き出し: %v\n", err)
			os.Exit(1)
		}
	}

	fmt.Fprintf(os.Stderr, "corpus=%d rows=%d\n", len(corpus), len(rows))
	if len(skipped) > 0 {
		keys := make([]string, 0, len(skipped))
		for k := range skipped {
			keys = append(keys, k)
		}
		sort.Strings(keys)
		fmt.Fprintln(os.Stderr, "未移植（行を出力していない）:")
		for _, k := range keys {
			fmt.Fprintf(os.Stderr, "  %-32s %d 件\n", k, skipped[k])
		}
	}
}

func readCorpus(path string) ([]entry, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()

	var out []entry
	sc := bufio.NewScanner(f)
	sc.Buffer(make([]byte, 0, 64*1024), 4*1024*1024)
	for sc.Scan() {
		if len(sc.Bytes()) == 0 {
			continue
		}
		var e entry
		if err := json.Unmarshal(sc.Bytes(), &e); err != nil {
			return nil, err
		}
		out = append(out, e)
	}
	return out, sc.Err()
}
