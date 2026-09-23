package lang

import "testing"

func TestIsWrongLanguage(t *testing.T) {
	cases := []struct {
		name string
		text string
		lang Lang
		want bool
	}{
		{
			// 2026-09 に実際に出たクイズ解説。ja 指定で韓国語になった。
			name: "ja に韓国語",
			text: "문장의 주어 자리에 지시 대명사인 นี่(nîi)를 사용합니다",
			lang: JA,
			want: true,
		},
		{
			name: "ja の通常の文",
			text: "主語の位置に指示代名詞 นี่ を置いて「これは〜だ」を作る",
			lang: JA,
			want: false,
		},
		{
			name: "ja のタイ語混じりの理由",
			text: "แกง（kɛɛng / カレー）：動詞の位置に名詞が入り文法上不自然",
			lang: JA,
			want: false,
		},
		{
			// 語義は漢字だけで正しいことがある。中国語ドリフトと区別できないが、
			// この長さなら日本語として成立するので通す。
			name: "ja の漢字だけの語義",
			text: "猫",
			lang: JA,
			want: false,
		},
		{
			name: "ja で文の長さなのに仮名が無い",
			text: "主語位置指示代名詞使用文章",
			lang: JA,
			want: true,
		},
		{
			// 2026-09 に prod で毎回弾かれていた ผม の語義。括弧で切れており
			// 漢字の連続は短い。日本語として正しいので通す。
			name: "ja の括弧で区切った漢字だけの語義",
			text: "私（男性一人称）",
			lang: JA,
			want: false,
		},
		{
			name: "ja の読点で区切った漢字だけの語義",
			text: "一人称代名詞、男性用",
			lang: JA,
			want: false,
		},
		{
			name: "ja に中国語",
			text: "我刚才坐在拳击场旁边",
			lang: JA,
			want: true,
		},
		{name: "ja に英語文", text: "This is written in English.", lang: JA, want: true},
		{name: "ja の英字固有名詞", text: "LINE", lang: JA, want: false},
		{name: "ja にタイ語だけ", text: "นี่คือเวลา", lang: JA, want: true},
		{
			name: "en の通常の理由",
			text: "แกง (kɛɛng / curry): a noun in a verb slot is ungrammatical",
			lang: EN,
			want: false,
		},
		{name: "en に日本語", text: "動詞の位置に名詞", lang: EN, want: true},
		{name: "en に韓国語", text: "문장의 주어 자리에", lang: EN, want: true},
		{name: "en にタイ語だけ", text: "นี่คือเวลา", lang: EN, want: true},
		{name: "空は見ない", text: "  ", lang: JA, want: false},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			if got := IsWrongLanguage(c.text, c.lang); got != c.want {
				t.Errorf("IsWrongLanguage(%q) = %v, want %v", c.text, got, c.want)
			}
		})
	}
}

func TestAnyWrongLanguage(t *testing.T) {
	if AnyWrongLanguage(JA, "主語の位置に置く語", "動詞の後ろ") {
		t.Error("正しい日本語を弾いた")
	}
	if !AnyWrongLanguage(JA, "主語の位置に置く語", "지시 대명사입니다") {
		t.Error("韓国語を見逃した")
	}
}
