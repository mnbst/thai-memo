package function

import (
	"context"
	"testing"

	"github.com/mnbst/thai-memo/functions/go/internal/callable"
)

func TestUnverifiedLimitReason(t *testing.T) {
	cases := []struct {
		name        string
		total, mine int
		want        string
	}{
		{"余裕あり", 0, 0, ""},
		{"1人の上限の手前", 10, unverifiedDailyPerUIDMax - 1, ""},
		{"1人の上限", 10, unverifiedDailyPerUIDMax, "uid"},
		{"全体の上限が先", unverifiedDailyTotalMax, unverifiedDailyPerUIDMax, "total"},
		{"全体の上限の手前", unverifiedDailyTotalMax - 1, 0, ""},
	}
	for _, c := range cases {
		if got := unverifiedLimitReason(c.total, c.mine); got != c.want {
			t.Errorf("%s: got %q, want %q", c.name, got, c.want)
		}
	}
}

// App Check が通っている・未ログインのリクエストは Firestore に触らず素通しする。
func TestLimitUnverifiedPassesThrough(t *testing.T) {
	called := 0
	h := limitUnverified("test", func(context.Context, *callable.Request) (any, error) {
		called++
		return nil, nil
	})
	reqs := []*callable.Request{
		{AppCheck: callable.AppCheckValid, Auth: &callable.Auth{UID: "u"}},
		{AppCheck: callable.AppCheckInvalid},
	}
	for _, r := range reqs {
		if _, err := h(context.Background(), r); err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
	}
	if called != len(reqs) {
		t.Fatalf("handler called %d times, want %d", called, len(reqs))
	}
}
