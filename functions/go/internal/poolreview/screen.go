package poolreview

// ネイティブ確認の前に Codex が判定した結果（sample -judged）と、表に載せる文の選び方。

import (
	"encoding/json"
	"fmt"
	"math"
	"math/rand/v2"
	"os"
)

// 表の枠（native_slot）。flagged は Codex が直したほうがよい（タイ語・訳を変える FIX か NG）とした文、
// ok は Codex が OK とした文（単語分解だけの直しも含む）。ok の枠でネイティブが直した割合が Codex の見逃し。
const (
	SlotFlagged = "flagged"
	SlotOK      = "ok"
)

// Judged は Codex の判定1件。Verdict は OK / FIX / NG。Fix は sentence と同じ形の一部。
type Judged struct {
	ID      string         `json:"id"`
	Verdict string         `json:"verdict"`
	Reason  string         `json:"reason"`
	Fix     map[string]any `json:"fix,omitempty"`
}

// ReadJudged は Codex の出力 {"results": [...]} を読む。
func ReadJudged(path string) (map[string]Judged, error) {
	raw, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var v struct {
		Results []Judged `json:"results"`
	}
	if err := json.Unmarshal(raw, &v); err != nil {
		return nil, err
	}
	out := make(map[string]Judged, len(v.Results))
	for _, j := range v.Results {
		switch j.Verdict {
		case VerdictOK, VerdictNG:
		case VerdictFix:
			if len(j.Fix) == 0 {
				return nil, fmt.Errorf("%s: FIX なのに fix が無い", j.ID)
			}
		default:
			return nil, fmt.Errorf("%s: verdict %q", j.ID, j.Verdict)
		}
		out[j.ID] = j
	}
	return out, nil
}

// PickNative は flagged・ok の候補から n 本選ぶ。flagged を n*share 本まで先に取り、残りを ok から取る。
// どちらかが足りなければもう一方で埋める。候補の並びは呼ぶ側で古い順などにしておく（先頭から取る）。
// 返す並びは混ぜてある（どちらの枠の文かを表の並びで分からないようにする）。
func PickNative(flagged, ok []string, n int, share float64, r *rand.Rand) (picked []string, slot map[string]string) {
	nf := int(math.Round(float64(n) * share))
	nf = min(nf, len(flagged))
	no := min(n-nf, len(ok))
	nf = min(n-no, len(flagged))
	slot = map[string]string{}
	for _, id := range flagged[:nf] {
		picked = append(picked, id)
		slot[id] = SlotFlagged
	}
	for _, id := range ok[:no] {
		picked = append(picked, id)
		slot[id] = SlotOK
	}
	r.Shuffle(len(picked), func(i, j int) { picked[i], picked[j] = picked[j], picked[i] })
	return picked, slot
}
