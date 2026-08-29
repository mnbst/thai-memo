// Package thainlp is the Go port of the Thai NLP stack currently provided by
// PyThaiNLPとTLTKを利用していた旧Python実装から移植したデータ。
//
// 移行時に生成したデータをGo実装の正本として保持する。
// 元データを更新したら再実行すること。
package thainlp

import (
	"bufio"
	"compress/gzip"
	"embed"
	"encoding/json"
	"fmt"
	"strings"
	"sync"
)

//go:embed data/sylrule.lts data/BEST.dict data/sylform_var.json data/sylseg_3g.jsonl.gz data/words_th.txt data/syllables_th.txt
//go:embed data/pos_tud_unigram.json data/pos_orchid_perceptron.json.gz data/orchid_maps.json data/pos_project.json data/sylrule_pron.json data/tdict.txt.gz
//go:embed data/PhSTrigram.jsonl.gz data/FrmSTrigram.jsonl.gz data/PhSBigram.jsonl.gz data/FrmSBigram.jsonl.gz
//go:embed data/PhSUnigram.jsonl.gz data/FrmSUnigram.jsonl.gz data/AbsUnigram.jsonl.gz data/AbsFrmSUnigram.jsonl.gz
var dataFS embed.FS

// Trigram キー。TLTK では (X, Y, Z) のタプル。
type triKey struct{ X, Y, Z string }

// biKey は (X, Y)。
type biKey struct{ X, Y string }

// Stats は TLTK の read_stat が構築する統計一式。
//
// 元実装（tltk/th2ipa.py:1421-1433）は pickle から TriCount だけを読み、
// 残りはそこから導出している。ここでも同じ導出をする。
type Stats struct {
	TriCount map[triKey]int
	BiCount  map[biKey]int
	BiType   map[biKey]int
	Count    map[string]int
	Type     map[string]int

	TotalWord int
	TotalLex  int
}

// Data は移植に必要な静的データをまとめたもの。
type Data struct {
	// SylRule は sylrule.lts の各行 "pattern,phone,type"。音韻規則の本体。
	SylRule []SylRule
	// Dict は BEST.dict の見出し語集合（既知語判定用）。
	Dict map[string]bool
	// SylVar は sylform_var.pick 由来の音節形バリエーション。
	SylVar map[string]any
	// Words / Syllables は PyThaiNLP の辞書。
	Words     []string
	Syllables []string

	Stats *Stats
}

// SylRule は sylrule.lts の1行。
type SylRule struct {
	Pattern string // タイ文字のパターン（A/K/T/X/C/R はクラス記号）
	Phone   string // 対応する音素列
	Kind    string // N など
}

var (
	loadOnce sync.Once
	loaded   *Data
	loadErr  error
)

// Load はデータを一度だけ読み込む。プロセス寿命の間キャッシュされる。
func Load() (*Data, error) {
	loadOnce.Do(func() { loaded, loadErr = load() })
	return loaded, loadErr
}

func load() (*Data, error) {
	d := &Data{Dict: map[string]bool{}}

	rules, err := readLines("data/sylrule.lts")
	if err != nil {
		return nil, err
	}
	for _, line := range rules {
		// "pattern,phone,kind" だが pattern 自体にカンマは現れない。
		parts := strings.Split(line, ",")
		if len(parts) < 3 {
			continue
		}
		d.SylRule = append(d.SylRule, SylRule{parts[0], parts[1], parts[2]})
	}

	words, err := readLines("data/BEST.dict")
	if err != nil {
		return nil, err
	}
	for _, w := range words {
		d.Dict[w] = true
	}

	if d.Words, err = readLines("data/words_th.txt"); err != nil {
		return nil, err
	}
	if d.Syllables, err = readLines("data/syllables_th.txt"); err != nil {
		return nil, err
	}

	raw, err := dataFS.ReadFile("data/sylform_var.json")
	if err != nil {
		return nil, err
	}
	if err := json.Unmarshal(raw, &d.SylVar); err != nil {
		return nil, fmt.Errorf("sylform_var.json: %w", err)
	}

	if d.Stats, err = loadStats(); err != nil {
		return nil, err
	}
	return d, nil
}

func readLines(name string) ([]string, error) {
	raw, err := dataFS.ReadFile(name)
	if err != nil {
		return nil, err
	}
	var out []string
	for _, line := range strings.Split(string(raw), "\n") {
		if line = strings.TrimRight(line, "\r"); line != "" {
			out = append(out, line)
		}
	}
	return out, nil
}

// loadStats は trigram を読み、BiCount / Count / Type / BiType / TotalWord /
// TotalLex を TLTK と同じ手順で導出する。
func loadStats() (*Stats, error) {
	f, err := dataFS.Open("data/sylseg_3g.jsonl.gz")
	if err != nil {
		return nil, err
	}
	defer f.Close()

	gz, err := gzip.NewReader(f)
	if err != nil {
		return nil, err
	}
	defer gz.Close()

	s := &Stats{
		TriCount: map[triKey]int{},
		BiCount:  map[biKey]int{},
		BiType:   map[biKey]int{},
		Count:    map[string]int{},
		Type:     map[string]int{},
	}

	sc := bufio.NewScanner(gz)
	sc.Buffer(make([]byte, 0, 64*1024), 4*1024*1024)
	for sc.Scan() {
		line := sc.Bytes()
		if len(line) == 0 {
			continue
		}
		var rec []json.RawMessage
		if err := json.Unmarshal(line, &rec); err != nil {
			return nil, fmt.Errorf("sylseg_3g: %w", err)
		}
		if len(rec) != 4 {
			return nil, fmt.Errorf("sylseg_3g: 要素数が %d", len(rec))
		}
		var x, y, z string
		var n int
		if err := json.Unmarshal(rec[0], &x); err != nil {
			return nil, err
		}
		if err := json.Unmarshal(rec[1], &y); err != nil {
			return nil, err
		}
		if err := json.Unmarshal(rec[2], &z); err != nil {
			return nil, err
		}
		if err := json.Unmarshal(rec[3], &n); err != nil {
			return nil, err
		}
		s.TriCount[triKey{x, y, z}] = n
	}
	if err := sc.Err(); err != nil {
		return nil, err
	}

	// tltk/th2ipa.py:1424-1433 と同じ導出
	for k, n := range s.TriCount {
		bk := biKey{k.X, k.Y}
		s.BiType[bk]++
		s.BiCount[bk] += n
		s.Count[k.Y] += n
	}
	for k := range s.BiCount {
		s.Type[k.X]++
	}
	for _, n := range s.Count {
		s.TotalLex++
		s.TotalWord += n
	}
	return s, nil
}
