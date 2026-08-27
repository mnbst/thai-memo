package uvm

import (
	"encoding/base64"
	"encoding/json"
	"math"
	"os"
	"testing"

	"github.com/mnbst/thai-memo/functions/go/internal/embeddings"
)

// sessionGoldenPath は
// functions/python/scripts/uvm_golden/gen_session_golden.py の出力。
// uvm.py の選定まわりを変えたら再生成すること。
const sessionGoldenPath = "../../../python/scripts/uvm_golden/session_golden.json"

type sessionGolden struct {
	NPYBase64 string            `json:"npy_base64"`
	Words     []embeddings.Word `json:"words"`
	FreqRank  FreqRank          `json:"freq_rank"`
	ScanBand  []struct {
		EstimatedVocab int   `json:"estimated_vocab"`
		Want           []int `json:"want"`
	} `json:"scan_band"`
	BandCandidates []struct {
		Low  int `json:"low"`
		High int `json:"high"`
		Want []struct {
			Word string `json:"word"`
			Rank int    `json:"rank"`
		} `json:"want"`
	} `json:"band_candidates"`
	Weights []struct {
		Candidates []struct {
			Word string `json:"word"`
			Rank int    `json:"rank"`
		} `json:"candidates"`
		PMap           map[string]float64 `json:"p_map"`
		ZeroWeights    []float64          `json:"zero_weights"`
		UnknownWeights []float64          `json:"unknown_weights"`
		ZeroPWords     []string           `json:"zero_p_words"`
	} `json:"weights"`
	FilterByTopic []struct {
		Low      int       `json:"low"`
		High     int       `json:"high"`
		TopicEmb []float32 `json:"topic_emb"`
		Want     []string  `json:"want"`
	} `json:"filter_by_topic"`
	ExposureP []struct {
		OldP  float64 `json:"old_p"`
		Count int     `json:"count"`
		Want  float64 `json:"want"`
	} `json:"exposure_p"`
	SentenceWords []struct {
		Words       []string `json:"words"`
		TargetWords []string `json:"target_words"`
		WantAll     []string `json:"want_all"`
		WantExposed []string `json:"want_exposed"`
	} `json:"sentence_words"`
}

func loadSessionGolden(t *testing.T) *sessionGolden {
	t.Helper()
	b, err := os.ReadFile(sessionGoldenPath)
	if err != nil {
		t.Fatalf("golden を読めない（gen_session_golden.py を実行したか？）: %v", err)
	}
	var g sessionGolden
	if err := json.Unmarshal(b, &g); err != nil {
		t.Fatalf("golden の JSON 解析に失敗: %v", err)
	}
	return &g
}

func near(a, b float64) bool { return math.Abs(a-b) < 1e-12 }

func TestScanBandAgainstPythonGolden(t *testing.T) {
	g := loadSessionGolden(t)
	for _, c := range g.ScanBand {
		low, high := ScanBand(c.EstimatedVocab)
		if low != c.Want[0] || high != c.Want[1] {
			t.Errorf("ScanBand(%d) = [%d %d], want %v", c.EstimatedVocab, low, high, c.Want)
		}
	}
	t.Logf("ランク帯の算出 %dケース一致", len(g.ScanBand))
}

func TestBandCandidatesAgainstPythonGolden(t *testing.T) {
	g := loadSessionGolden(t)
	for _, c := range g.BandCandidates {
		got := BandCandidates(g.FreqRank, c.Low, c.High)
		if len(got) != len(c.Want) {
			t.Fatalf("BandCandidates(%d,%d) 件数 %d, want %d", c.Low, c.High, len(got), len(c.Want))
		}
		for i := range got {
			if got[i].Word != c.Want[i].Word || got[i].Rank != c.Want[i].Rank {
				t.Fatalf("BandCandidates(%d,%d)[%d] = %v, want %v",
					c.Low, c.High, i, got[i], c.Want[i])
			}
		}
	}
	t.Logf("候補の切り出し %dケース一致", len(g.BandCandidates))
}

func TestSelectionWeightsAgainstPythonGolden(t *testing.T) {
	g := loadSessionGolden(t)
	for ci, c := range g.Weights {
		cands := make([]Candidate, len(c.Candidates))
		for i, x := range c.Candidates {
			cands[i] = Candidate{Word: x.Word, Rank: x.Rank}
		}
		zero := ZeroPWeights(cands)
		for i := range zero {
			if !near(zero[i], c.ZeroWeights[i]) {
				t.Fatalf("case %d: ZeroPWeights[%d] = %v, want %v", ci, i, zero[i], c.ZeroWeights[i])
			}
		}
		unknown := UnknownWeights(cands, c.PMap)
		for i := range unknown {
			if !near(unknown[i], c.UnknownWeights[i]) {
				t.Fatalf("case %d: UnknownWeights[%d] = %v, want %v", ci, i, unknown[i], c.UnknownWeights[i])
			}
		}
		var zeroP []string
		for _, x := range cands {
			if p, ok := c.PMap[x.Word]; !ok || p == 0.0 {
				zeroP = append(zeroP, x.Word)
			}
		}
		if !equalStrings(zeroP, c.ZeroPWords) {
			t.Fatalf("case %d: zero_p = %q, want %q", ci, zeroP, c.ZeroPWords)
		}
	}
	t.Logf("抽選の重み %dケース一致", len(g.Weights))
}

func TestFilterCandidatesByTopicAgainstPythonGolden(t *testing.T) {
	g := loadSessionGolden(t)
	npy, err := base64.StdEncoding.DecodeString(g.NPYBase64)
	if err != nil {
		t.Fatalf("npy の base64 を戻せない: %v", err)
	}
	store := &embeddings.Store{}
	if err := store.LoadFromBytes(npy, g.Words); err != nil {
		t.Fatalf("embedding を読み込めない: %v", err)
	}

	for ci, c := range g.FilterByTopic {
		cands := BandCandidates(g.FreqRank, c.Low, c.High)
		got := FilterCandidatesByTopic(store, cands, c.TopicEmb, g.FreqRank, c.Low)
		var words []string
		for _, x := range got {
			words = append(words, x.Word)
		}
		if !equalStrings(words, c.Want) {
			t.Fatalf("case %d (%d..%d): = %q, want %q", ci, c.Low, c.High, words, c.Want)
		}
	}
	t.Logf("テーマでの候補絞り込み %dケース一致", len(g.FilterByTopic))
}

func TestExposurePAgainstPythonGolden(t *testing.T) {
	g := loadSessionGolden(t)
	for _, c := range g.ExposureP {
		if got := ExposureP(c.OldP, c.Count); !near(got, c.Want) {
			t.Errorf("ExposureP(%v, %d) = %v, want %v", c.OldP, c.Count, got, c.Want)
		}
	}
	t.Logf("露出による P 更新 %dケース一致", len(g.ExposureP))
}

func TestSentenceWordsAgainstPythonGolden(t *testing.T) {
	g := loadSessionGolden(t)
	for ci, c := range g.SentenceWords {
		gotAll := SentenceWords(c.Words)
		if !equalStrings(gotAll, c.WantAll) {
			t.Fatalf("case %d: SentenceWords = %q, want %q", ci, gotAll, c.WantAll)
		}
		gotExposed := ExposedWords(c.Words, c.TargetWords)
		if !equalStrings(gotExposed, c.WantExposed) {
			t.Fatalf("case %d: ExposedWords = %q, want %q", ci, gotExposed, c.WantExposed)
		}
	}
	t.Logf("例文の語の抽出 %dケース一致", len(g.SentenceWords))
}

func equalStrings(a, b []string) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if a[i] != b[i] {
			return false
		}
	}
	return true
}
