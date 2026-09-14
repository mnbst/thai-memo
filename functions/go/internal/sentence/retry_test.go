package sentence

import "strings"

import "testing"

func TestBuildRetryConstraint(t *testing.T) {
	if got := BuildRetryConstraint(nil); got != "" {
		t.Errorf("notes 無しで %q", got)
	}
	if got := BuildRetryConstraint([]string{"  ", ""}); got != "" {
		t.Errorf("空白だけの notes で %q", got)
	}

	got := BuildRetryConstraint([]string{
		"หน่วย は食べ物の量には使わない",
		"  ",
		"訳文に「いつも」を足している",
	})
	for _, want := range []string{
		"【やり直し】", "1. หน่วย は食べ物の量には使わない",
		"2. 訳文に「いつも」を足している",
	} {
		if !strings.Contains(got, want) {
			t.Errorf("%q を含まない:\n%s", want, got)
		}
	}
	if strings.Contains(got, "3.") {
		t.Errorf("空白だけの note が番号を取っている:\n%s", got)
	}
}
