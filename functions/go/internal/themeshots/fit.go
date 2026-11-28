package themeshots

import (
	"context"
	"encoding/json"
	"regexp"
	"sync"

	"github.com/mnbst/thai-memo/functions/go/internal/bldrama"
	"github.com/mnbst/thai-memo/functions/go/internal/sentence"
)

// 場面合致の候補に、学習語がその場面で自然に使えるかの点を付ける（sentence.SceneFitter）。
//
// 埋め込みの近さは語と場面が関係しているかを測るだけで、その場面で語を使う一言が
// 言えるかは分けられない。足切りを通った組を Codex が判定した891組で、合う・合わないの
// AUC は表の z 0.54・作り方を変えた埋め込みでも最大 0.63、この問いの Decisions は 0.85
// （2026-11-28）。表の点はそのまま足切りに使い、選ぶときだけこの点で比べる。

// Asker は quality.Gemini.Ask（Decisions API に問いを noul で聞く）。
type Asker interface {
	Ask(ctx context.Context, input string, questions map[string]string) (map[string]float64, error)
}

// FitScorer は場面の候補ごとに Decisions で点を付ける。
type FitScorer struct {
	Asker Asker
}

// sceneFitQuestion は「この場面で key_word を自然に使えるか」の問い。891組で測った文面。
const sceneFitQuestion = "`key_word` を、その普通の意味のまま使う自然な一言を、タイ語の母語話者がこの場面（`scene`・`situation`）の中で言える。場面の本筋から外れた話題を足さないと `key_word` が出てこないものは当てはまらない"

// sceneSuffixRe は場面名の末尾の出どころの印（「スマホ用品を探す（エピソード）」）。
// 測ったときと同じく外して聞く。
var sceneSuffixRe = regexp.MustCompile(`（(物語|エピソード|旅先の交流|寺の事件)?[0-9０-９]*）$`)

// SceneFit は picks の順に、word がその場面で自然に使えるかの点（0〜1）を返す。
// 候補は並列に聞く。1つでも失敗したらエラー（呼び出し側は従来の選び方に戻す）。
func (f *FitScorer) SceneFit(ctx context.Context, word string, picks []sentence.ScenePick) ([]float64, error) {
	out := make([]float64, len(picks))
	errs := make([]error, len(picks))
	var wg sync.WaitGroup
	for i, p := range picks {
		wg.Add(1)
		go func() {
			defer wg.Done()
			ans, err := f.Asker.Ask(ctx, fitInput(word, p), map[string]string{"fit": sceneFitQuestion})
			if err != nil {
				errs[i] = err
				return
			}
			out[i] = ans["fit"]
		}()
	}
	wg.Wait()
	for _, err := range errs {
		if err != nil {
			return nil, err
		}
	}
	return out, nil
}

// fitInput は Decisions に渡す入力。測ったときと同じキー（key_word・scene・situation・example）。
func fitInput(word string, p sentence.ScenePick) string {
	var text, scene, situation string
	if p.Topic == sentence.Topics[15] {
		text, scene = bldrama.ShotLine(p.ShotID)
	} else {
		text, scene = shots[p.ShotID], sceneSuffixRe.ReplaceAllString(shotScene[p.ShotID], "")
		situation = shotSituation[p.ShotID]
	}
	if situation == "" {
		situation = scene
	}
	// キーの順は測ったときと揃える（map だと辞書順になる）。
	b, _ := json.Marshal(struct {
		KeyWord   string `json:"key_word"`
		Scene     string `json:"scene"`
		Situation string `json:"situation"`
		Example   string `json:"example"`
	}{word, scene, situation, text})
	return string(b)
}
