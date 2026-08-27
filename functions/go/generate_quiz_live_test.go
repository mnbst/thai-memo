package function

import (
	"fmt"
	"testing"
	"time"
)

// SRS 例文選出を dev の実 Firestore で確かめる。
// Firestore のクエリ（日付範囲・in・orderBy）が絡むので、実データで見る。
//
//	GCLOUD_PROJECT=thai-memo-dev LIVE_FIRESTORE_TEST=1 \
//	  go test -run TestSelectSentences -v .

// fixedShuffle は並べ替えを恒等にする（選出の順序依存を消す）。
func fixedShuffle(t *testing.T) {
	t.Helper()
	original := shuffleN
	shuffleN = func(n int, swap func(i, j int)) {}
	t.Cleanup(func() { shuffleN = original })
}

// TestStartOfJstDayDaysAgo は SRS のクエリ境界を確かめる。
//
// 「N日前の JST 0:00 から24時間」に作られた例文だけを拾う。ここがずれると
// 復習が1日前後にずれる。
func TestStartOfJstDayDaysAgo(t *testing.T) {
	// JST 2026-08-27 08:00（= UTC 2026-08-26 23:00）を nowJST() 相当で表す。
	// nowJST() は UTC の時計に +9h した値なので、そのまま UTC として扱う。
	jstNow := time.Date(2026, 8, 27, 8, 0, 0, 0, time.UTC)

	tests := []struct {
		daysAgo int
		want    string
	}{
		{0, "2026-08-26T15:00:00Z"}, // JST 8/27 0:00
		{1, "2026-08-25T15:00:00Z"}, // JST 8/26 0:00
		{3, "2026-08-23T15:00:00Z"},
		{7, "2026-08-19T15:00:00Z"},
		{14, "2026-08-12T15:00:00Z"},
		{30, "2026-07-27T15:00:00Z"},
	}
	for _, tt := range tests {
		t.Run(fmt.Sprintf("%d日前", tt.daysAgo), func(t *testing.T) {
			want, err := time.Parse(time.RFC3339, tt.want)
			if err != nil {
				t.Fatal(err)
			}
			if got := startOfJstDayDaysAgo(jstNow, tt.daysAgo); !got.Equal(want) {
				t.Errorf("want %s, got %s", want, got.UTC())
			}
		})
	}
}

// TestSelectSentencesBySRS は SRS 選出と UVM 補充を実 Firestore で確かめる。
func TestSelectSentencesBySRS(t *testing.T) {
	db, ctx := liveFirestore(t)
	fixedShuffle(t)

	const uid = "go-port-srs-throwaway"
	sentences := db.Collection("users").Doc(uid).Collection("sentences")
	uvm := db.Collection("users").Doc(uid).Collection("uvm")

	// nowJST() と同じ表し方（UTC の時計に +9h）
	jstNow := time.Now().UTC().Add(jstOffset)
	// 各 SRS 間隔のちょうど中間の時刻に作られたことにする
	at := func(daysAgo int) time.Time {
		return startOfJstDayDaysAgo(jstNow, daysAgo).Add(12 * time.Hour)
	}

	type seed struct {
		id        string
		keyWord   string
		thai      string
		createdAt time.Time
	}
	seeds := []seed{
		// 1日前: 同じ日に2件。P が低い方（low-p）が選ばれるはず
		{"s-1d-lowp", "กิน", "ฉันกินข้าว", at(1)},
		{"s-1d-highp", "ไป", "ฉันไปตลาด", at(1)},
		// 3日前
		{"s-3d", "แมว", "ฉันมีแมว", at(3)},
		// 7日前
		{"s-7d", "สวย", "เธอสวยมาก", at(7)},
		// key_word が本文に無い → 対象外
		{"s-3d-broken", "ไม่มี", "ฉันมีแมว", at(3)},
		// SRS の日付に当たらない（5日前）→ 補充でのみ拾われうる
		{"s-5d-filler", "น้ำ", "ฉันดื่มน้ำ", at(5)},
		{"s-5d-filler2", "บ้าน", "ฉันอยู่บ้าน", at(5)},
	}

	t.Cleanup(func() {
		for _, s := range seeds {
			_, _ = sentences.Doc(s.id).Delete(ctx)
		}
		for _, w := range []string{"กิน", "ไป", "แมว", "สวย", "น้ำ", "บ้าน"} {
			_, _ = uvm.Doc(w).Delete(ctx)
		}
		_, _ = db.Collection("users").Doc(uid).Delete(ctx)
	})

	for _, s := range seeds {
		if _, err := sentences.Doc(s.id).Set(ctx, map[string]any{
			"thai_text":              s.thai,
			"pronunciation":          "chǎn kin khâao",
			"japanese_translation":   "訳",
			"key_word":               s.keyWord,
			"key_word_pronunciation": "kin",
			"key_word_meaning":       "意味",
			"created_at":             s.createdAt,
		}); err != nil {
			t.Fatal(err)
		}
	}

	// UVM。補充は「2回以上出題して P が低い」語を優先する。
	uvmSeeds := map[string]map[string]any{
		"กิน":  {"p": 0.1, "quiz_attempts": int64(0)}, // 1日前の2件のうち低い方
		"ไป":   {"p": 0.9, "quiz_attempts": int64(0)},
		"แมว":  {"p": 0.5, "quiz_attempts": int64(0)},
		"สวย":  {"p": 0.5, "quiz_attempts": int64(0)},
		"น้ำ":  {"p": 0.25, "quiz_attempts": int64(5)}, // weak: 優先される
		"บ้าน": {"p": 0.05, "quiz_attempts": int64(1)}, // P は低いが weak ではない
	}
	for word, data := range uvmSeeds {
		if _, err := uvm.Doc(word).Set(ctx, data); err != nil {
			t.Fatal(err)
		}
	}

	selected, err := selectSentencesBySRS(ctx, db, uid, jstNow)
	if err != nil {
		t.Fatal(err)
	}

	byID := map[string]int{}
	for _, s := range selected {
		byID[s.ID] = s.SrsInterval
	}
	t.Logf("選出: %v", byID)

	if len(selected) > maxQuestions {
		t.Errorf("上限を超えている: %d 件", len(selected))
	}

	// SRS 枠は最大2件。1日前と3日前が当たる（7日前は枠に入らない）。
	var srsCount int
	for _, s := range selected {
		if s.SrsInterval > 0 {
			srsCount++
		}
	}
	if srsCount != maxSrsSentences {
		t.Errorf("SRS 枠: want %d, got %d（%v）", maxSrsSentences, srsCount, byID)
	}

	// 1日前の2件からは P の低い กิน 側が選ばれる
	if interval, ok := byID["s-1d-lowp"]; !ok || interval != 1 {
		t.Errorf("1日前は P の低い s-1d-lowp が選ばれるはず: %v", byID)
	}
	if _, ok := byID["s-1d-highp"]; ok {
		t.Errorf("同じ日から2件選ばれている: %v", byID)
	}

	// key_word が本文に無い例文は選ばれない
	if _, ok := byID["s-3d-broken"]; ok {
		t.Errorf("key_word が本文に無い例文が選ばれている: %v", byID)
	}

	// 補充は weak な น้ำ が บ้าน より先
	fillerOrder := []string{}
	for _, s := range selected {
		if s.SrsInterval == -1 {
			fillerOrder = append(fillerOrder, s.ID)
		}
	}
	if len(fillerOrder) < 2 {
		t.Fatalf("補充が2件未満: %v", fillerOrder)
	}
	if fillerOrder[0] != "s-5d-filler" {
		t.Errorf("weak な語（น้ำ, quiz_attempts>=2 かつ p<0.3）が先に来るはず: %v",
			fillerOrder)
	}
}

// TestSelectSentencesBySRSNoSentences は例文が1件も無いときに空を返すことを確かめる。
// クライアントはこれを no_user_sentences として受ける。
func TestSelectSentencesBySRSNoSentences(t *testing.T) {
	db, ctx := liveFirestore(t)
	fixedShuffle(t)

	selected, err := selectSentencesBySRS(ctx, db,
		"go-port-srs-empty-throwaway", time.Now().UTC().Add(jstOffset))
	if err != nil {
		t.Fatal(err)
	}
	if len(selected) != 0 {
		t.Errorf("例文が無いのに %d 件選ばれた", len(selected))
	}
}
