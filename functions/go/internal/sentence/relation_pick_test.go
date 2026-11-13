package sentence

import (
	"context"
	"strings"
	"testing"

	"github.com/mnbst/thai-memo/functions/go/internal/lang"
)

// 性別を決めるターゲット語は、抽選せずその性別にする。
func TestResolveSpeakerFollowsGenderedTarget(t *testing.T) {
	r := &Resolver{}
	for i := 0; i < 50; i++ {
		if got := r.Resolve(context.Background(), nil, []string{"ผม"}, 200); got.RelationSpeaker != "男性" {
			t.Fatalf("ผม: speaker=%q", got.RelationSpeaker)
		}
		if got := r.Resolve(context.Background(), nil, []string{"ค่ะ"}, 200); got.RelationSpeaker != "女性" {
			t.Fatalf("ค่ะ: speaker=%q", got.RelationSpeaker)
		}
	}
}

// 関係を指定しない premium の対面回は、地位の既定値を渡し、relation を enum で LLM に書かせる。
func TestBuildPromptRelationPick(t *testing.T) {
	resolved := ResolvedParams{
		Topic: Topics[0], RelationStatus: "自分より目上", RelationSpeaker: "女性",
	}
	prompt, rc := BuildPrompt(resolved, []string{"กิน"}, 200, true, lang.JA, DramaSection{})
	if !strings.Contains(prompt, "話し手は女性。相手は自分より目上。") {
		t.Errorf("関係ブロックに既定の地位と性別が無い:\n%s", prompt)
	}
	ask, ok := rc["relation"].(RelationAsk)
	if !ok || ask.Speaker != "女性" {
		t.Fatalf("context.relation=%#v", rc["relation"])
	}
	schema := SchemaFor(rc, lang.JA)
	props := schema["properties"].(map[string]any)["context"].(map[string]any)["properties"].(map[string]any)
	enum, _ := props["relation"].(map[string]any)["enum"].([]any)
	if len(enum) != 3 || enum[0] != "自分より目上／女性" {
		t.Errorf("enum=%v", enum)
	}

	// 生成した relation は確定値で上書きしない。
	s := &Sentence{Context: map[string]any{"relation": "自分と対等／女性"}}
	ApplyResponseCompat(s, rc)
	if s.Context["relation"] != "自分と対等／女性" {
		t.Errorf("relation=%v", s.Context["relation"])
	}
}

// free は関係ブロックを持たない。
func TestBuildPromptRelationPickFree(t *testing.T) {
	resolved := ResolvedParams{Topic: Topics[0], RelationStatus: "自分より目上", RelationSpeaker: "女性"}
	prompt, rc := BuildPrompt(resolved, []string{"กิน"}, 200, false, lang.JA, DramaSection{})
	if strings.Contains(prompt, "【話し手と聞き手】") {
		t.Error("free に関係ブロックが付いた")
	}
	if _, ok := rc["relation"]; ok {
		t.Errorf("free に relation が付いた: %v", rc["relation"])
	}
}
