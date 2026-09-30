package function

import (
	"reflect"
	"testing"
	"time"
)

func daily(setID string, viewed any) map[string]any {
	data := map[string]any{"daily": true}
	if setID != "" {
		data["daily_set_id"] = setID
	}
	if viewed != nil {
		data["viewed"] = viewed
	}
	return data
}

func TestUnreadDeliveredSetIDs(t *testing.T) {
	cases := []struct {
		name string
		docs []deliveredDoc
		want []string
	}{
		{
			name: "今回配信したセットは残す",
			docs: []deliveredDoc{
				{ID: "new1", Data: daily("new1", false)},
				{ID: "new2", Data: daily("new1", false)},
			},
		},
		{
			name: "まるごと未読の旧セットは消す",
			docs: []deliveredDoc{
				{ID: "new1", Data: daily("new1", false)},
				{ID: "old1", Data: daily("old1", false)},
				{ID: "old2", Data: daily("old1", false)},
			},
			want: []string{"old1"},
		},
		{
			name: "1本でも既読なら消さない",
			docs: []deliveredDoc{
				{ID: "old1", Data: daily("old1", true)},
				{ID: "old2", Data: daily("old1", false)},
			},
		},
		{
			name: "viewed 無しは既読扱いで消さない",
			docs: []deliveredDoc{
				{ID: "old1", Data: daily("old1", nil)},
			},
		},
		{
			name: "旧形式（daily_set_id 無し）は1本1セット",
			docs: []deliveredDoc{
				{ID: "solo", Data: daily("", false)},
			},
			want: []string{"solo"},
		},
		{
			name: "複数の旧セットを doc ID 昇順で返す",
			docs: []deliveredDoc{
				{ID: "b1", Data: daily("b1", false)},
				{ID: "a1", Data: daily("a1", false)},
			},
			want: []string{"a1", "b1"},
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got := unreadDeliveredSetIDs(tc.docs, "new1")
			if len(got) == 0 && len(tc.want) == 0 {
				return
			}
			if !reflect.DeepEqual(got, tc.want) {
				t.Errorf("unreadDeliveredSetIDs() = %v, want %v", got, tc.want)
			}
		})
	}
}

func TestDeliveredSetID(t *testing.T) {
	if got := deliveredSetID("doc1", daily("set1", nil)); got != "set1" {
		t.Errorf("daily_set_id を優先しない: %q", got)
	}
	if got := deliveredSetID("doc1", daily("", nil)); got != "doc1" {
		t.Errorf("旧形式は doc ID: %q", got)
	}
	if got := deliveredSetID("doc1", map[string]any{"daily_set_id": ""}); got != "doc1" {
		t.Errorf("空文字は doc ID: %q", got)
	}
}

func TestUnreadDeliveredSetIDsSkipsPurged(t *testing.T) {
	purged := daily("old1", false)
	purged["deleted"] = true
	docs := []deliveredDoc{
		{ID: "new1", Data: daily("new1", false)},
		{ID: "old1", Data: purged},
	}
	// 削除印つきは数え直さない（印を付け直して updated_at を動かさない）。
	if got := unreadDeliveredSetIDs(docs, "new1"); len(got) != 0 {
		t.Fatalf("got %v, want none", got)
	}
}

func TestExpiredPurgedDocIDs(t *testing.T) {
	now := time.Date(2026, 9, 30, 0, 0, 0, 0, time.UTC)
	doc := func(deleted bool, purgedAgo time.Duration) map[string]any {
		data := daily("s", false)
		if deleted {
			data["deleted"] = true
		}
		if purgedAgo > 0 {
			data["purged_at"] = now.Add(-purgedAgo)
		}
		return data
	}
	docs := []deliveredDoc{
		{ID: "expired", Data: doc(true, purgedSentenceRetention)},
		{ID: "fresh", Data: doc(true, purgedSentenceRetention-time.Hour)},
		{ID: "userDeleted", Data: doc(true, 0)},
		{ID: "live", Data: doc(false, 0)},
	}
	if got, want := expiredPurgedDocIDs(docs, now), []string{"expired"}; !reflect.DeepEqual(got, want) {
		t.Fatalf("got %v, want %v", got, want)
	}
}
