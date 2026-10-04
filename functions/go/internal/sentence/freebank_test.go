package sentence

import (
	"context"
	"math/rand"
	"testing"

	"github.com/mnbst/thai-memo/functions/go/internal/lang"
)

// TestFreeBankPickTopic はテーマ一致の優先と、在庫の無いテーマの扱いを見る。
func TestFreeBankPickTopic(t *testing.T) {
	const travel, food, transport = "旅行", "食べ物", "交通"
	b := &FreeBank{
		Rand: rand.New(rand.NewSource(1)),
		cache: map[lang.Lang][]Sentence{lang.JA: {
			{ThaiText: "a", KeyWord: "ไป", Context: map[string]any{"topic": travel}},
			{ThaiText: "b", KeyWord: "ไป", Context: map[string]any{"topic": food}},
			{ThaiText: "c", KeyWord: "กิน", Context: map[string]any{"topic": food}},
		}},
	}
	pick := func(word, topic string) *Sentence {
		t.Helper()
		s, err := b.Pick(context.Background(), word, lang.JA, topic, false)
		if err != nil {
			t.Fatal(err)
		}
		return s
	}

	for range 10 {
		if s := pick("ไป", travel); s == nil || s.ThaiText != "a" {
			t.Fatalf("テーマ一致を優先していない: %+v", s)
		}
	}
	// 語にそのテーマの文が無くても、バンクにテーマがあれば別テーマで埋める。
	if s := pick("กิน", travel); s == nil || s.ThaiText != "c" {
		t.Fatalf("在庫のあるテーマで別テーマへ逃がしていない: %+v", s)
	}
	// バンクに1本も無いテーマは生成へ落とす。
	if s := pick("ไป", transport); s != nil {
		t.Fatalf("在庫の無いテーマで在庫を返した: %+v", s)
	}
	if s := pick("ไป", ""); s == nil {
		t.Fatal("テーマ無しで在庫を返さない")
	}
	if s := pick("นอน", travel); s != nil {
		t.Fatalf("語の在庫が無いのに返した: %+v", s)
	}
}
