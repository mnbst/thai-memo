package embeddings

import (
	"encoding/base64"
	"encoding/json"
	"math"
	"os"
	"reflect"
	"testing"
)

type embeddingsGolden struct {
	Dim         int    `json:"dim"`
	NpyBase64   string `json:"npy_base64"`
	Words       []Word `json:"words"`
	CosineCases []struct {
		A   int     `json:"a"`
		B   int     `json:"b"`
		Sim float64 `json:"sim"`
	} `json:"cosine_cases"`
	FilterCases []struct {
		Candidates []string `json:"candidates"`
		Selected   []string `json:"selected"`
		Threshold  float64  `json:"threshold"`
		Result     []string `json:"result"`
	} `json:"filter_cases"`
	DiverseCases []struct {
		Candidates []string `json:"candidates"`
		Count      int      `json:"count"`
		Threshold  float64  `json:"threshold"`
		Result     []string `json:"result"`
	} `json:"diverse_cases"`
	WeightCases []struct {
		Sims    []float64  `json:"sims"`
		Weights *[]float64 `json:"weights"`
	} `json:"weight_cases"`
}

func loadEmbeddingsGolden(t *testing.T) (*embeddingsGolden, *Store) {
	t.Helper()
	raw, err := os.ReadFile(
		"../../../python/scripts/daily_golden/embeddings_golden.json")
	if err != nil {
		t.Fatalf("golden の読み込みに失敗: %v", err)
	}
	var golden embeddingsGolden
	if err := json.Unmarshal(raw, &golden); err != nil {
		t.Fatal(err)
	}

	npy, err := base64.StdEncoding.DecodeString(golden.NpyBase64)
	if err != nil {
		t.Fatal(err)
	}
	store := &Store{}
	if err := store.LoadFromBytes(npy, golden.Words); err != nil {
		t.Fatalf("npy の読み込みに失敗: %v", err)
	}
	return &golden, store
}

// TestParseNPY は numpy が書いた .npy を正しく読めることを確かめる。
//
// numpy を持ち込まずに自前で読んでいるので、行数・次元・値の一致を直接見る。
func TestParseNPY(t *testing.T) {
	golden, store := loadEmbeddingsGolden(t)

	if len(store.matrix) != len(golden.Words) {
		t.Fatalf("行数: want %d, got %d", len(golden.Words), len(store.matrix))
	}
	for i, row := range store.matrix {
		if len(row) != golden.Dim {
			t.Fatalf("行 %d の次元: want %d, got %d", i, golden.Dim, len(row))
		}
	}

	// 語からの逆引きが行に対応していること
	for i, w := range golden.Words {
		emb := store.Embedding(w.Word)
		if emb == nil {
			t.Fatalf("%s の embedding が引けない", w.Word)
		}
		if !reflect.DeepEqual(emb, store.matrix[i]) {
			t.Errorf("%s が行 %d を指していない", w.Word, i)
		}
	}
	if store.Embedding("存在しない語") != nil {
		t.Error("未知語に embedding が返っている")
	}
}

// TestCosineSimilarityGolden はコサイン類似度を numpy の結果と突き合わせる。
//
// numpy は float32 で積和して float64 にするので、Go 側も同じ順序で計算しないと
// 下位桁がずれる。重複除去は閾値との比較なので、境界付近でずれると結果が変わる。
func TestCosineSimilarityGolden(t *testing.T) {
	golden, store := loadEmbeddingsGolden(t)
	if len(golden.CosineCases) == 0 {
		t.Fatal("golden が空")
	}

	const eps = 1e-6
	var maxDiff float64
	var zeroCases int

	for _, c := range golden.CosineCases {
		got := CosineSimilarity(store.matrix[c.A], store.matrix[c.B])
		if c.Sim == 0 {
			zeroCases++
		}
		diff := math.Abs(got - c.Sim)
		maxDiff = math.Max(maxDiff, diff)
		if diff > eps {
			t.Errorf("cos(%d,%d): Python=%.12f Go=%.12f 差=%g",
				c.A, c.B, c.Sim, got, diff)
		}
	}

	t.Logf("%d ケース一致（最大誤差 %g、ゼロベクトル絡み %d）",
		len(golden.CosineCases), maxDiff, zeroCases)
	if zeroCases == 0 {
		t.Error("ゼロベクトルのケースが無い。golden が退化している")
	}
}

// TestFilterSemanticDuplicatesGolden は重複除去を Python 実装と突き合わせる。
func TestFilterSemanticDuplicatesGolden(t *testing.T) {
	golden, store := loadEmbeddingsGolden(t)
	if len(golden.FilterCases) == 0 {
		t.Fatal("golden が空")
	}

	var removedSomething, unknownKept int
	for i, c := range golden.FilterCases {
		got := store.FilterSemanticDuplicates(
			toWords(c.Candidates), toWords(c.Selected), c.Threshold)

		if len(got) < len(c.Candidates) {
			removedSomething++
		}
		for _, w := range c.Result {
			if w == "unknown" {
				unknownKept++
				break
			}
		}

		if !reflect.DeepEqual(wordStrings(got), normalizeStrings(c.Result)) {
			t.Errorf("case %d (threshold=%v):\n  候補   = %v\n  選定済 = %v\n"+
				"  Python = %v\n  Go     = %v",
				i, c.Threshold, c.Candidates, c.Selected, c.Result, wordStrings(got))
		}
	}

	t.Logf("%d ケース一致（除去あり %d / 未知語を残した %d）",
		len(golden.FilterCases), removedSomething, unknownKept)
	if removedSomething == 0 || unknownKept == 0 {
		t.Error("除去ありか未知語のどちらかが踏まれていない")
	}
}

// TestGetDiverseNewWordsGolden は貪欲選出を Python 実装と突き合わせる。
func TestGetDiverseNewWordsGolden(t *testing.T) {
	golden, store := loadEmbeddingsGolden(t)
	if len(golden.DiverseCases) == 0 {
		t.Fatal("golden が空")
	}

	var truncated, skipped int
	for i, c := range golden.DiverseCases {
		got := store.GetDiverseNewWords(toWords(c.Candidates), c.Count, c.Threshold)

		if len(c.Result) == c.Count && c.Count > 0 && len(c.Candidates) > c.Count {
			truncated++
		}
		if len(c.Result) < len(c.Candidates) && len(c.Result) < c.Count {
			skipped++
		}

		if !reflect.DeepEqual(wordStrings(got), normalizeStrings(c.Result)) {
			t.Errorf("case %d (count=%d threshold=%v):\n  候補   = %v\n"+
				"  Python = %v\n  Go     = %v",
				i, c.Count, c.Threshold, c.Candidates, c.Result, wordStrings(got))
		}
	}

	t.Logf("%d ケース一致（件数で打ち切り %d / 類似で除外 %d）",
		len(golden.DiverseCases), truncated, skipped)
	if truncated == 0 || skipped == 0 {
		t.Error("打ち切りか除外のどちらかが踏まれていない")
	}
}

// TestPickWeightsGolden は重みつき抽選の重みを Python 実装と突き合わせる。
//
// 実際にどれが選ばれるかは乱数の実装依存なので比べられない。
// 重みの計算までを固定し、抽選そのものは Store.pick 側で差し替え可能にしてある。
func TestPickWeightsGolden(t *testing.T) {
	golden, _ := loadEmbeddingsGolden(t)
	if len(golden.WeightCases) == 0 {
		t.Fatal("golden が空")
	}

	const eps = 1e-12
	var uniform int

	for i, c := range golden.WeightCases {
		got, ok := PickWeights(c.Sims)

		if c.Weights == nil {
			uniform++
			if ok {
				t.Errorf("case %d: Python は一様抽選なのに Go は重みを返した: %v",
					i, got)
			}
			continue
		}
		if !ok {
			t.Errorf("case %d: Python は重みを返したのに Go は一様抽選", i)
			continue
		}
		want := *c.Weights
		if len(got) != len(want) {
			t.Errorf("case %d: 長さ Python=%d Go=%d", i, len(want), len(got))
			continue
		}
		for j := range want {
			if math.Abs(got[j]-want[j]) > eps {
				t.Errorf("case %d[%d]: Python=%.15f Go=%.15f", i, j, want[j], got[j])
			}
		}
	}

	t.Logf("%d ケース一致（全て同点で一様抽選 %d）", len(golden.WeightCases), uniform)
	if uniform == 0 {
		t.Error("同点ケースが無い。golden が退化している")
	}
}

func toWords(names []string) []Word {
	out := make([]Word, 0, len(names))
	for _, n := range names {
		out = append(out, Word{Word: n})
	}
	return out
}

func wordStrings(words []Word) []string {
	out := make([]string, 0, len(words))
	for _, w := range words {
		out = append(out, w.Word)
	}
	return out
}

// normalizeStrings は nil と空スライスの差を吸収する。
func normalizeStrings(s []string) []string {
	if s == nil {
		return []string{}
	}
	return s
}
