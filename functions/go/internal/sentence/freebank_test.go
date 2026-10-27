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

// TestFreeBankPickUnseen は語に紐づく文をバンクの並び順で、未出のものから返すこと。
// テーマでは絞らない。
func TestFreeBankPickUnseen(t *testing.T) {
	b := &FreeBank{cache: map[lang.Lang][]Sentence{lang.JA: {
		{ThaiText: "a", KeyWord: "ไป", Context: map[string]any{"topic": "旅行"}},
		{ThaiText: "x", KeyWord: "กิน", Context: map[string]any{"topic": "食べ物"}},
		{ThaiText: "b", KeyWord: "ไป", Context: map[string]any{"topic": "食べ物"}},
	}}}
	pick := func(seen map[string]bool) (string, string) {
		t.Helper()
		s, topic, err := b.PickUnseen(context.Background(), "ไป", lang.JA, seen)
		if err != nil {
			t.Fatal(err)
		}
		if s == nil {
			return "", topic
		}
		return s.ThaiText, topic
	}
	if got, topic := pick(nil); got != "a" || topic != "旅行" {
		t.Errorf("1本目 = %q (%s), want a (旅行)", got, topic)
	}
	if got, topic := pick(map[string]bool{"a": true}); got != "b" || topic != "食べ物" {
		t.Errorf("a が既出なら = %q (%s), want b (食べ物)", got, topic)
	}
	if got, _ := pick(map[string]bool{"a": true, "b": true}); got != "" {
		t.Errorf("全部既出なのに %q", got)
	}
	if s, _, _ := b.PickUnseen(context.Background(), "นอน", lang.JA, nil); s != nil {
		t.Errorf("バンクに無い語で %q", s.ThaiText)
	}
}
