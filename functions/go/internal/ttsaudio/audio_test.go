package ttsaudio

import (
	"context"
	"errors"
	"slices"
	"testing"
)

func TestNormalize(t *testing.T) {
	cases := map[string]string{
		"  สวัสดี   ครับ ": "สวัสดี ครับ",
		"ไปกินข้าว 😋🍜 กัน": "ไปกินข้าว กัน",
		"ใจ❤️\nดี":         "ใจ ดี",
		"👍":                "",
	}
	for in, want := range cases {
		if got := Normalize(in); got != want {
			t.Errorf("Normalize(%q) = %q, want %q", in, got, want)
		}
	}
}

func TestGender(t *testing.T) {
	pron := func(w string) Word { return Word{Word: w, GrammaticalRole: "代名詞", Meaning: "私"} }
	cases := []struct {
		name string
		in   Input
		want gender
	}{
		{"文末ครับ", Input{ThaiText: "ไปก่อนนะครับ"}, male},
		{"文末ค่ะ・記号", Input{ThaiText: "ขอบคุณค่ะ!"}, female},
		{"文末คะ", Input{ThaiText: "ใช่ไหมคะ"}, female},
		{"文末คับは単語のときだけ", Input{ThaiText: "ไม่บังคับ"}, unknown},
		{"文末คับ（単語）", Input{ThaiText: "ได้คับ", Words: []Word{{Word: "ได้"}, {Word: "คับ"}}}, male},
		{"บังคับ（単語）", Input{ThaiText: "ห้ามบังคับ", Words: []Word{{Word: "ห้าม"}, {Word: "บังคับ"}}}, unknown},
		{"一人称ผม", Input{ThaiText: "ผมชอบกาแฟ", Words: []Word{pron("ผม"), {Word: "ชอบ"}, {Word: "กาแฟ"}}}, male},
		{"髪のผม", Input{ThaiText: "ผมยาว", Words: []Word{{Word: "ผม", GrammaticalRole: "名詞", Meaning: "髪"}, {Word: "ยาว"}}}, unknown},
		{"一人称หนู", Input{ThaiText: "หนูหิว", Words: []Word{pron("หนู"), {Word: "หิว"}}}, female},
		{"文末が一人称より先", Input{ThaiText: "ผมว่าดีค่ะ", Words: []Word{pron("ผม"), {Word: "ว่า"}, {Word: "ดี"}, {Word: "ค่ะ"}}}, female},
		{"BL", Input{ThaiText: "คิดถึงนะ", Topic: "タイBLドラマ（告白）"}, male},
		{"BLでも文末ค่ะ", Input{ThaiText: "เชิญค่ะ", Topic: "タイBLドラマ"}, female},
		{"手がかりなし", Input{ThaiText: "ฝนตก"}, unknown},
	}
	for _, c := range cases {
		if got := genderOf(Normalize(c.in.ThaiText), c.in); got != c.want {
			t.Errorf("%s: got %v want %v", c.name, got, c.want)
		}
	}
}

func TestChooseVoiceStable(t *testing.T) {
	in := Input{ThaiText: "ไปก่อนนะครับ"}
	v := ChooseVoice(in.ThaiText, in)
	if !slices.Contains(maleVoices, v) {
		t.Fatalf("male voice expected, got %s", v)
	}
	for range 5 {
		if ChooseVoice(in.ThaiText, in) != v {
			t.Fatal("voice must not change between calls")
		}
	}
	// 手がかりなしでも同じ文は同じ声。
	plain := Input{ThaiText: "ฝนตก"}
	if ChooseVoice("ฝนตก", plain) != ChooseVoice("ฝนตก", plain) {
		t.Fatal("hash voice must be stable")
	}
}

type fakeStore struct{ m map[string][]byte }

func (f *fakeStore) Get(_ context.Context, name string) ([]byte, bool, error) {
	d, ok := f.m[name]
	return d, ok, nil
}

func (f *fakeStore) Create(_ context.Context, name string, data []byte) error {
	if _, ok := f.m[name]; !ok {
		f.m[name] = data
	}
	return nil
}

type failingStore struct{ fakeStore }

func (f *failingStore) Create(context.Context, string, []byte) error { return errors.New("gcs down") }

func TestEnsureReturnsAudioWhenStoreFails(t *testing.T) {
	store := &failingStore{fakeStore{m: map[string][]byte{}}}
	res, err := Ensure(context.Background(), store, &fakeSynth{}, Input{ThaiText: "ฝนตก"})
	if err != nil || len(res.Audio) == 0 || res.StoreErr == nil {
		t.Fatalf("res=%+v err=%v", res, err)
	}
}

type fakeSynth struct{ calls int }

func (f *fakeSynth) Synthesize(_ context.Context, voice, text string) ([]byte, error) {
	f.calls++
	return []byte(voice + ":" + text), nil
}

func TestEnsure(t *testing.T) {
	ctx := context.Background()
	store, synth := &fakeStore{m: map[string][]byte{}}, &fakeSynth{}
	in := Input{ThaiText: "สวัสดี  ครับ 🙏"}

	first, err := Ensure(ctx, store, synth, in)
	if err != nil || !first.Created || synth.calls != 1 {
		t.Fatalf("first: %+v err=%v calls=%d", first, err, synth.calls)
	}
	// 空白・絵文字が違っても同じファイルを使い、作り直さない。
	second, err := Ensure(ctx, store, synth, Input{ThaiText: "สวัสดี ครับ"})
	if err != nil || second.Created || synth.calls != 1 || second.Object != first.Object {
		t.Fatalf("second: %+v err=%v calls=%d", second, err, synth.calls)
	}
	if string(second.Audio) != string(first.Audio) {
		t.Fatal("audio mismatch")
	}
	if _, err := Ensure(ctx, store, synth, Input{ThaiText: "🙏"}); !errors.Is(err, ErrEmpty) {
		t.Fatalf("want ErrEmpty, got %v", err)
	}
}
