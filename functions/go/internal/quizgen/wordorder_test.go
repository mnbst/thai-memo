package quizgen

import (
	"math/rand"
	"strings"
	"testing"
)

func wordOrderWords(texts ...string) []WordOrderWord {
	out := make([]WordOrderWord, 0, len(texts))
	for _, t := range texts {
		out = append(out, WordOrderWord{Text: t, Pronunciation: "p-" + t})
	}
	return out
}

func TestBuildWordOrderContainsKeyWord(t *testing.T) {
	words := wordOrderWords("ผม", "อยาก", "ไป", "ทะเล", "กับ", "เพื่อน", "ครับ")
	for seed := range 50 {
		wo, ok := BuildWordOrder("ผมอยากไปทะเลกับเพื่อนครับ", words, "ทะเล",
			rand.New(rand.NewSource(int64(seed))))
		if !ok {
			t.Fatalf("seed %d: 作れなかった", seed)
		}
		if len(wo.Answer) != WordOrderSize || !contains(wo.Answer, "ทะเล") {
			t.Fatalf("seed %d: 枠に key_word が無い %v", seed, wo.Answer)
		}
		// 枠の外と正解をつなぐと本文に戻る
		if got := wo.Prefix + strings.Join(wo.Answer, "") + wo.Suffix; got != "ผมอยากไปทะเลกับเพื่อนครับ" {
			t.Fatalf("seed %d: 本文に戻らない %q", seed, got)
		}
		if strings.Join(wo.Tiles, "") == strings.Join(wo.Answer, "") {
			t.Fatalf("seed %d: 混ざっていない %v", seed, wo.Tiles)
		}
		for i, tile := range wo.Tiles {
			if wo.TilePronunciations[i] != "p-"+tile {
				t.Fatalf("seed %d: 発音の対応がずれた %v %v", seed, wo.Tiles, wo.TilePronunciations)
			}
		}
	}
}

func TestBuildWordOrderKeepsSpaces(t *testing.T) {
	words := wordOrderWords("วันนี้", "ร้อน", "มาก", "นะ", "ไป", "ทะเล")
	wo, ok := BuildWordOrder("วันนี้ร้อนมากนะ ไปทะเล", words, "ทะเล", rand.New(rand.NewSource(1)))
	if !ok {
		t.Fatal("作れなかった")
	}
	if wo.Prefix != "วันนี้ร้อน" || wo.Suffix != "" {
		t.Fatalf("prefix=%q suffix=%q", wo.Prefix, wo.Suffix)
	}
	if wo.PrefixPronunciation != "p-วันนี้ p-ร้อน" {
		t.Fatalf("prefix pron=%q", wo.PrefixPronunciation)
	}
}

func TestBuildWordOrderRejects(t *testing.T) {
	rnd := rand.New(rand.NewSource(1))
	cases := []struct {
		name  string
		text  string
		words []WordOrderWord
		key   string
	}{
		{"短い", "ผมกินข้าว", wordOrderWords("ผม", "กิน", "ข้าว"), "กิน"},
		{"本文に戻らない", "ผมกินข้าวแล้ว", wordOrderWords("ผม", "กิน", "ข้าว", "นะ"), "กิน"},
		{"key_word が無い", "ผมกินข้าวแล้ว", wordOrderWords("ผม", "กิน", "ข้าว", "แล้ว"), "ไป"},
		{"記号入り", "ผม?กินข้าว", wordOrderWords("ผม", "?", "กิน", "ข้าว"), "กิน"},
		{"同じ語が2つ", "ดีมากมากเลย", wordOrderWords("ดี", "มาก", "มาก", "เลย"), "ดี"},
	}
	for _, c := range cases {
		if _, ok := BuildWordOrder(c.text, c.words, c.key, rnd); ok {
			t.Errorf("%s: 作れてしまった", c.name)
		}
	}
}

func contains(values []string, target string) bool {
	for _, v := range values {
		if v == target {
			return true
		}
	}
	return false
}
