package quality

import (
	"encoding/json"
	"testing"

	"github.com/mnbst/thai-memo/functions/go/internal/lang"
)

func TestReviewPoolAsksOnlyPoolAspects(t *testing.T) {
	batch := sample(2)
	batch[1].ThaiText = "odd"
	s := &jevServer{scores: map[string]map[string]float64{
		// 生成時の観点が高くても、プールの判定では聞かないので落ちない。
		"ผมกินข้าว": {"collocation": 0.9},
		"odd":       {"situation": 0.5},
	}}
	res, err := newJudge(t, s).ReviewPool(t.Context(), batch)
	if err != nil {
		t.Fatal(err)
	}
	if len(res.Accepted) != 1 || len(res.Flagged) != 1 || res.Flagged[0].ThaiText != "odd" {
		t.Fatalf("odd だけが落ちるはず: %+v", res)
	}
	var body struct {
		Questions map[string]any `json:"questions"`
	}
	_ = json.Unmarshal(s.last.Load().([]byte), &body)
	if len(body.Questions) != len(PoolAspects) {
		t.Fatalf("プールの観点だけを聞くはず: %v", body.Questions)
	}
}

func TestReviewPoolSkipsTranslationAspectForEnglish(t *testing.T) {
	batch := sample(1)
	batch[0].Lang = lang.EN
	s := &jevServer{scores: map[string]map[string]float64{
		"ผมกินข้าว": {"tmean": 0.9},
	}}
	res, err := newJudge(t, s).ReviewPool(t.Context(), batch)
	if err != nil {
		t.Fatal(err)
	}
	if len(res.Accepted) != 1 {
		t.Fatalf("英訳には tmean を聞かないので通るはず: %+v", res)
	}
}

func TestPoolThresholds(t *testing.T) {
	cases := []struct {
		scores map[string]float64
		bad    bool
	}{
		{map[string]float64{"situation": 0.35, "tmean": 0.4, "name": 0.4}, false},
		{map[string]float64{"situation": 0.36, "tmean": 0.1, "name": 0.1}, true},
		{map[string]float64{"situation": 0.1, "tmean": 0.41, "name": 0.1}, true},
		{map[string]float64{"situation": 0.1, "tmean": 0.1, "name": 0.41}, true},
	}
	c := sample(1)[0]
	for _, tc := range cases {
		if _, bad := verdictFrom(0, aspectsIn(PoolAspects, c), tc.scores); bad != tc.bad {
			t.Errorf("%v: bad=%v want %v", tc.scores, bad, tc.bad)
		}
	}
}
