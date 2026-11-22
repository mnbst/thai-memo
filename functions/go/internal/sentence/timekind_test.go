package sentence

import (
	"context"
	"math/rand"
	"slices"
	"strings"
	"testing"
)

func TestTimeKindCandidates(t *testing.T) {
	cases := []struct {
		frame string
		words []string
		want  []string
	}{
		// คง は見通しだけ（予定・意志・願望は閾値未満）。
		{TimeFrames[2], []string{"คง"}, []string{"この先そうなりそうなこと"}},
		// เคย は経験と昔（特定の日の出来事は合わない）。
		{TimeFrames[4], []string{"เคย"}, []string{"前にしたことがある経験", "昔はそうだったこと"}},
		// ช่วงนี้ は最近続いていること。
		{TimeFrames[3], []string{"ช่วงนี้"}, []string{"最近続いていること"}},
		// 表に無い語は絞らない。
		{TimeFrames[0], []string{"ไม่มีคำนี้"}, TimeKinds[0]},
		// 種類を持たない時点（さっき）は nil。
		{TimeFrames[1], []string{"คง"}, nil},
	}
	for _, c := range cases {
		if got := TimeKindCandidates(c.frame, c.words); !slices.Equal(got, c.want) {
			t.Errorf("TimeKindCandidates(%s, %v) = %v, want %v", c.frame, c.words, got, c.want)
		}
	}
}

func TestTimeKindInPrompt(t *testing.T) {
	r := &Resolver{Rand: rand.New(rand.NewSource(1))}
	res := r.Resolve(context.Background(), map[string]any{"timeFrame": TimeFrames[2]}, []string{"คง"}, 800)
	if res.TimeFrame != TimeFrames[2] || res.TimeKind != "この先そうなりそうなこと" {
		t.Fatalf("TimeFrame=%q TimeKind=%q", res.TimeFrame, res.TimeKind)
	}
	if got := timeFrameShown(res.TimeFrame, res.TimeKind); !strings.Contains(got, "この先") {
		t.Errorf("時点の行 = %q", got)
	}
}
