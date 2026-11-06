package thainlp

import "testing"

func TestTagWordsContext(t *testing.T) {
	cases := []struct {
		name  string
		words []string
		index int
		want  string
	}{
		{"ของ 持ち主", []string{"หนังสือ", "ของ", "ฉัน"}, 1, "前置詞"},
		{"ของ 動詞の後でも代名詞なら持ち主", []string{"เดินทาง", "ของ", "ฉัน"}, 1, "前置詞"},
		{"ของ 動詞の目的語", []string{"ซื้อ", "ของ"}, 1, "名詞"},
		{"ของ 類別詞の前", []string{"ของ", "ชิ้น", "นี้"}, 0, "名詞"},
		{"ของ 関係節の前", []string{"ราคา", "ของ", "ที่", "ซื้อ"}, 1, "名詞"},
		{"ที่ 場所", []string{"วาง", "ที่", "โต๊ะ"}, 1, "前置詞"},
		{"ที่ 関係節", []string{"ร้าน", "ที่", "คน", "แนะนำ"}, 1, "代名詞"},
		{"ที่ 動詞の前", []string{"คน", "ที่", "มา"}, 1, "代名詞"},
		{"ที่ ตาม の後", []string{"ตาม", "ที่", "พี่"}, 1, "代名詞"},
		{"ที่ ตอน の後", []string{"ตอน", "ที่", "แมว", "อ้อน"}, 1, "代名詞"},
		{"ที่ ทุกครั้ง の後", []string{"ทุกครั้ง", "ที่", "การบ้าน"}, 1, "代名詞"},
		{"ขึ้น 形容詞の後", []string{"ดี", "ขึ้น"}, 1, "助動詞"},
		{"ไป 本動詞", []string{"จะ", "ไป"}, 1, "動詞"},
		{"ไป 動詞の後", []string{"หาย", "ไป"}, 1, "助動詞"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			got, err := TagWords(c.words)
			if err != nil {
				t.Fatal(err)
			}
			if got[c.index] != c.want {
				t.Errorf("%v[%d] = %q, want %q", c.words, c.index, got[c.index], c.want)
			}
		})
	}
}
