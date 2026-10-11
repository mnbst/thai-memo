package sentence

import "testing"

func TestReplaceNames(t *testing.T) {
	names := map[string]string{"แกง": "カン", "Kang": "カン", "ข้าวแกง": "カオゲーン", "Er": "アー"}
	ctx := map[string]any{
		"usage_scenarios": "ข้าวแกงを売る先輩のแกงが、Kangと呼ばれる場面。Errorは変えない。Erが話す。",
		"cultural_notes":  "",
	}
	replaceNames(ctx, names)
	want := "カオゲーンを売る先輩のカンが、カンと呼ばれる場面。Errorは変えない。アーが話す。"
	if got := ctx["usage_scenarios"]; got != want {
		t.Errorf("got %q, want %q", got, want)
	}
}
