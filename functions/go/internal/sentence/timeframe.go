package sentence

import (
	_ "embed"
	"encoding/json"
	"sync"
)

// time_frames.json は語 → TimeFrames の各時点に自然に置けるかの確率（並びは
// TimeFrames と同じ）。頻度上位の語について Jev で事前に判定した
// （scripts/build_time_frames.py）。
//
// 時点を一様に引くと、語と時点がぶつかる（พรุ่งนี้ に「さっき」）うえ、
// 過去が「さっき」に偏った。語が自然に置ける時点の中から引くことで両方を避ける。
//
//go:embed time_frames.json
var timeFramesJSON []byte

// timeFrameFitThreshold 以上の時点を、その語の候補にする。
const timeFrameFitThreshold = 0.5

var (
	timeFrameFitOnce sync.Once
	timeFrameFit     map[string][]float64
)

func loadTimeFrameFit() map[string][]float64 {
	timeFrameFitOnce.Do(func() {
		if err := json.Unmarshal(timeFramesJSON, &timeFrameFit); err != nil {
			panic("time_frames.json: " + err.Error())
		}
	})
	return timeFrameFit
}

// TimeFrameCandidates は語が自然に置ける時点を返す。
//
// 語が複数なら全語に合う時点に絞る。表に無い語は絞り込みに使わない。
// どの時点も閾値に届かない語は、確率が最も高い時点だけを候補にする。
// 絞った結果が空になるか、表に載った語が無ければ TimeFrames 全体を返す。
func TimeFrameCandidates(words []string) []string {
	table := loadTimeFrameFit()
	ok := make([]bool, len(TimeFrames))
	for i := range ok {
		ok[i] = true
	}
	known := false
	for _, w := range words {
		probs, found := table[w]
		if !found || len(probs) != len(TimeFrames) {
			continue
		}
		known = true
		best := 0
		for i, p := range probs {
			if p > probs[best] {
				best = i
			}
		}
		for i, p := range probs {
			if p < timeFrameFitThreshold && i != best {
				ok[i] = false
			}
		}
	}
	var out []string
	for i, frame := range TimeFrames {
		if ok[i] {
			out = append(out, frame)
		}
	}
	if !known || len(out) == 0 {
		return TimeFrames
	}
	return out
}
