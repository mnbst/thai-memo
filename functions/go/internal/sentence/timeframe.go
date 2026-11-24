package sentence

import (
	_ "embed"
	"encoding/json"
	"strconv"
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
	return fitCandidates(loadTimeFrameFit(), TimeFrames, words)
}

// fitCandidates は語×選択肢の確率表から、全語に合う選択肢を返す（TimeFrameCandidates の規則）。
func fitCandidates(table map[string][]float64, options, words []string) []string {
	ok := make([]bool, len(options))
	for i := range ok {
		ok[i] = true
	}
	known := false
	for _, w := range words {
		probs, found := table[w]
		if !found || len(probs) != len(options) {
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
	for i, o := range options {
		if ok[i] {
			out = append(out, o)
		}
	}
	if !known || len(out) == 0 {
		return options
	}
	return out
}

// TimeKinds は時点ごとの種類（時点の位置 → 言い方）。プロンプトの時点の行には引いた種類の言い方を出す。
// 1つの時点の言い方だけだと、時の言い方がその代表の形に偏る（「これからの予定」なら日時の決まった
// 予定の文ばかりで、意志・見通し・願望の文が出ない。2026-11-22、prompt-effect-ledger）。
// 「さっき起きた出来事」は分けない（十分に絞れていて、เมื่อกี้・เพิ่ง がよく出る）。
var TimeKinds = map[int][]string{
	0: {"今している最中のこと", "今の状態や気持ち"},
	2: {"これからの予定", "これからそうしようと決めていること", "この先そうなりそうなこと", "これからそうなってほしいこと"},
	3: {"いつもの習慣", "最近続いていること"},
	4: {"昨日や以前の出来事", "前にしたことがある経験", "昔はそうだったこと"},
}

// time_kinds.json は語 → {時点の位置: TimeKinds の各種類に自然に置けるかの確率}。
// time_frames.json でその時点が候補の語について Gemini Decisions で判定した（scripts/build_time_kinds.py）。
//
//go:embed time_kinds.json
var timeKindsJSON []byte

var (
	timeKindFitOnce sync.Once
	timeKindFit     map[string]map[string][]float64
)

// TimeKindCandidates は時点 timeFrame で、語が自然に置ける種類を返す（規則は TimeFrameCandidates と同じ）。
// 種類を持たない時点なら nil。
func TimeKindCandidates(timeFrame string, words []string) []string {
	idx := -1
	for i, f := range TimeFrames {
		if f == timeFrame {
			idx = i
		}
	}
	kinds := TimeKinds[idx]
	if len(kinds) == 0 {
		return nil
	}
	timeKindFitOnce.Do(func() {
		if err := json.Unmarshal(timeKindsJSON, &timeKindFit); err != nil {
			panic("time_kinds.json: " + err.Error())
		}
	})
	key := strconv.Itoa(idx)
	table := make(map[string][]float64, len(words))
	for _, w := range words {
		if p, ok := timeKindFit[w][key]; ok {
			table[w] = p
		}
	}
	return fitCandidates(table, kinds, words)
}

// TimeFrameDisplay はプロンプトに出す時点の言い方の差し替え（試し生成用。本番は nil）。
// 抽選と但し書きは元の値のまま、行に出す文言だけを変える。
var TimeFrameDisplay map[string]string

// CoarseTimeFrames は時点を粗くした言い方（過去／現在／未来／習慣）。cmd/sample -coarse-time。
var CoarseTimeFrames = map[string]string{
	"今まさに起きていること": "現在",
	"さっき起きた出来事":   "過去",
	"昨日や以前の出来事":   "過去",
	"これからの予定":     "未来",
	"いつもの習慣":      "習慣",
}

func timeFrameShown(tf, kind string) string {
	if kind != "" {
		return kind
	}
	if v, ok := TimeFrameDisplay[tf]; ok {
		return v
	}
	return tf
}
