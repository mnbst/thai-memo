package function

import (
	"bufio"
	"encoding/json"
	"math/rand"
	"os"
	"sort"
	"strconv"
	"strings"
	"testing"

	"github.com/mnbst/thai-memo/functions/go/internal/quizgen"
	"github.com/mnbst/thai-memo/functions/go/internal/uvm"
)

// TestPickDistractorsLive は実データ（freq_rank と静的コーパス）で
// ダミー選択肢の選定結果を目視する。品詞タガーを実際に動かすので、
// 通常のテスト実行からは外してある。
//
//	go test ./ -run TestPickDistractorsLive -v -tags= -args
//	QUIZ_DISTRACTOR_LIVE=1 go test ./ -run TestPickDistractorsLive -v
func TestPickDistractorsLive(t *testing.T) {
	if os.Getenv("QUIZ_DISTRACTOR_LIVE") == "" {
		t.Skip("QUIZ_DISTRACTOR_LIVE=1 で実行する")
	}
	freqRank := loadLocalFreqRank(t)
	sorted := make([]rankedWord, 0, len(freqRank))
	for word, rank := range freqRank {
		sorted = append(sorted, rankedWord{word: word, rank: rank})
	}
	sort.Slice(sorted, func(i, j int) bool { return sorted[i].rank < sorted[j].rank })
	vocab := &quizVocab{freqRank: freqRank, sorted: sorted, pos: map[string]string{}}

	rnd := rand.New(rand.NewSource(1))
	var tried, filled int
	for _, row := range loadCorpusSample(t, 40) {
		tried++
		dummies := quizgen.PickDistractors(vocab, row.target, row.words, rnd)
		if len(dummies) == 0 {
			t.Logf("― %s（%s）ダミーを選べず → LLM 生成へ", row.thai, row.target)
			continue
		}
		filled++
		parts := make([]string, len(dummies))
		for i, d := range dummies {
			rank, _ := vocab.Rank(d)
			pos, _ := vocab.POS(d)
			parts[i] = d + "(" + pos + "/rank" + itoa(rank) + ")"
		}
		answerRank, _ := vocab.Rank(row.target)
		answerPOS, trusted := vocab.POS(row.target)
		mark := ""
		if !trusted {
			mark = "*" // 辞書に無く、単体タグ付けで決めた品詞
		}
		t.Logf("○ %s\n   正解 %s(%s%s/rank%d)  ダミー %s",
			row.thai, row.target, answerPOS, mark, answerRank, strings.Join(parts, " "))
	}
	t.Logf("選定できた %d/%d", filled, tried)
}

func itoa(n int) string { return strconv.Itoa(n) }

type corpusSample struct {
	thai       string
	target     string
	targetPron string
	words      []string
}

func loadLocalFreqRank(t *testing.T) uvm.FreqRank {
	t.Helper()
	f, err := os.Open("../../scripts/corpus/freq_rank_top10000.json")
	if err != nil {
		t.Skipf("freq_rank が無い: %v", err)
	}
	defer f.Close()
	var raw map[string]int
	if err := json.NewDecoder(f).Decode(&raw); err != nil {
		t.Fatal(err)
	}
	return uvm.FreqRank(raw)
}

func loadCorpusSample(t *testing.T, n int) []corpusSample {
	t.Helper()
	f, err := os.Open("../../scripts/corpus/corpus.jsonl")
	if err != nil {
		t.Skipf("コーパスが無い: %v", err)
	}
	defer f.Close()
	var out []corpusSample
	sc := bufio.NewScanner(f)
	sc.Buffer(make([]byte, 1<<22), 1<<22)
	for sc.Scan() && len(out) < n {
		var row struct {
			ThaiText   string `json:"thai_text"`
			TargetWord string `json:"target_word"`
			Words      []struct {
				Word          string `json:"word"`
				Pronunciation string `json:"pronunciation"`
			} `json:"words"`
		}
		if json.Unmarshal(sc.Bytes(), &row) != nil {
			continue
		}
		words := make([]string, len(row.Words))
		targetPron := ""
		for i, w := range row.Words {
			words[i] = w.Word
			if w.Word == row.TargetWord {
				targetPron = w.Pronunciation
			}
		}
		out = append(out, corpusSample{
			thai: row.ThaiText, target: row.TargetWord,
			targetPron: targetPron, words: words,
		})
	}
	return out
}
