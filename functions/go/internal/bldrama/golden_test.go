package bldrama

import (
	"context"
	"encoding/json"
	"errors"
	"math/rand"
	"os"
	"reflect"
	"testing"

	"github.com/mnbst/thai-memo/functions/go/internal/embeddings"
)

// bldrama_golden.json は
// functions/python/scripts/daily_golden/gen_bldrama_golden.py が
// 本物の themes/bl_drama.py を呼んで書き出したもの。

type golden struct {
	Sections []struct {
		ShotID   string `json:"shot_id"`
		Shot     string `json:"shot"`
		Context  string `json:"context"`
		Required string `json:"required"`
	} `json:"sections"`
	ShotIDs     []string          `json:"shot_ids"`
	Shots       map[string]string `json:"shots"`
	ShotContext map[string]struct {
		Drama   string `json:"drama"`
		Context string `json:"context"`
		Scene   string `json:"scene"`
	} `json:"shot_context"`
}

func load(t *testing.T) *golden {
	t.Helper()
	raw, err := os.ReadFile("../../../python/scripts/daily_golden/bldrama_golden.json")
	if err != nil {
		t.Fatalf("golden の読み込みに失敗: %v", err)
	}
	var g golden
	if err := json.Unmarshal(raw, &g); err != nil {
		t.Fatal(err)
	}
	return &g
}

// TestDataGolden は生成データ（data.go）が Python 側と一致しているかを見る。
// gen_bldrama.py の再実行を忘れると、ここで気付く。
func TestDataGolden(t *testing.T) {
	g := load(t)
	if !reflect.DeepEqual(shots, g.Shots) {
		t.Error("shots 不一致")
	}
	if !reflect.DeepEqual(shotIDs, g.ShotIDs) {
		t.Errorf("shotIDs 不一致\ngot  %v\nwant %v", shotIDs, g.ShotIDs)
	}
	for sid, want := range g.ShotContext {
		got, ok := shotContext[sid]
		if !ok {
			t.Errorf("%s が無い", sid)
			continue
		}
		if got.Drama != want.Drama || got.Context != want.Context ||
			got.Scene != want.Scene {
			t.Errorf("%s の逆引きが不一致: %+v want %+v", sid, got, want)
		}
	}
	if len(shotContext) != len(g.ShotContext) {
		t.Errorf("shotContext の件数 %d want %d", len(shotContext), len(g.ShotContext))
	}
	t.Logf("セリフ %d 件、逆引き %d 件が一致", len(shots), len(shotContext))
}

// TestBuildDramaSectionGolden はプロンプト断片が Python と一字一句同じかを見る。
func TestBuildDramaSectionGolden(t *testing.T) {
	g := load(t)
	for _, c := range g.Sections {
		b := &Builder{Shots: fixedShot(c.ShotID)}
		got := b.BuildDramaSection([]string{"กิน"})
		if got.Context != c.Context {
			t.Errorf("%s context 不一致\ngot  %q\nwant %q", c.ShotID, got.Context, c.Context)
		}
		if got.Required != c.Required {
			t.Errorf("%s required 不一致\ngot  %q\nwant %q", c.ShotID, got.Required, c.Required)
		}
	}
	t.Logf("%d ケース一致", len(g.Sections))
}

type fixedShot string

func (f fixedShot) FindBestDramaShot(
	context.Context, string, []embeddings.Shot,
) (string, error) {
	return string(f), nil
}

type failingShot struct{ calls int }

func (f *failingShot) FindBestDramaShot(
	context.Context, string, []embeddings.Shot,
) (string, error) {
	f.calls++
	return "", errors.New("embedding が引けない")
}

// TestPickShotFallback は選出できないときにランダムへ縮退することを見る。
//
// ここで例文生成ごと落とすと、BL 回だけ配信が止まる。
func TestPickShotFallback(t *testing.T) {
	cases := []struct {
		name        string
		targetWords []string
		finder      ShotFinder
	}{
		{"ターゲット語が無い", nil, fixedShot("ob_01")},
		{"embedding が失敗", []string{"กิน"}, &failingShot{}},
		{"選出が空を返す", []string{"กิน"}, fixedShot("")},
		{"finder が無い", []string{"กิน"}, nil},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			b := &Builder{Rand: rand.New(rand.NewSource(1)), Shots: tc.finder}
			seen := map[string]bool{}
			for i := 0; i < 2000; i++ {
				id := b.PickShot(tc.targetWords)
				if _, ok := shotContext[id]; !ok {
					t.Fatalf("知らないショットID: %q", id)
				}
				seen[id] = true
			}
			if len(seen) != len(shotIDs) {
				t.Errorf("引かれたショット %d 種 want %d", len(seen), len(shotIDs))
			}
		})
	}
}

// TestPickShotUsesFirstTargetWord は先頭のターゲット語で引くことを見る。
func TestPickShotUsesFirstTargetWord(t *testing.T) {
	f := &recordingShot{result: "hk_01"}
	b := &Builder{Shots: f}
	if got := b.PickShot([]string{"กิน", "ไป"}); got != "hk_01" {
		t.Errorf("shot=%q want hk_01", got)
	}
	if f.word != "กิน" {
		t.Errorf("引いた語=%q want กิน", f.word)
	}
	if len(f.shots) != len(shotIDs) {
		t.Errorf("候補 %d 件 want %d", len(f.shots), len(shotIDs))
	}
}

type recordingShot struct {
	result string
	word   string
	shots  []embeddings.Shot
}

func (r *recordingShot) FindBestDramaShot(
	_ context.Context, word string, shots []embeddings.Shot,
) (string, error) {
	r.word = word
	r.shots = shots
	return r.result, nil
}
