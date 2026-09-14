package sentence

import (
	"context"
	"os"
	"testing"
	"time"

	"github.com/mnbst/thai-memo/functions/go/internal/lang"
)

// 実 GCS のコーパスバンクを読み、語が引けることと読み込みの重さを確かめる。
// 書き込みはしない。
//
//	CORPUS_BANK_PROJECT=thai-memo-dev LIVE_CORPUS_BANK_TEST=1 \
//	  go test -run TestCorpusBankLive -v -timeout 5m ./internal/sentence
//
// 認証は gcloud auth application-default login 済みであること。
func TestCorpusBankLive(t *testing.T) {
	if os.Getenv("LIVE_CORPUS_BANK_TEST") != "1" {
		t.Skip("LIVE_CORPUS_BANK_TEST=1 のときだけ実行する")
	}
	project := os.Getenv("CORPUS_BANK_PROJECT")
	if project == "" {
		t.Fatal("CORPUS_BANK_PROJECT が要る")
	}

	ctx := context.Background()
	for _, l := range []lang.Lang{lang.JA, lang.EN} {
		bank := &CorpusBank{ProjectID: project}

		start := time.Now()
		index, err := bank.Load(ctx, l)
		if err != nil {
			t.Fatalf("%s のバンクを読めない: %v", l, err)
		}
		elapsed := time.Since(start)
		if len(index) == 0 {
			t.Fatalf("%s のバンクが空（アップロード済みか？）", l)
		}

		sentences := 0
		for _, list := range index {
			sentences += len(list)
		}
		t.Logf("lang=%s 語=%d 文=%d 読み込み=%v",
			l, len(index), sentences, elapsed.Round(time.Millisecond))

		// 2回目はキャッシュに当たるので GCS を叩かない。
		start = time.Now()
		if _, err := bank.Load(ctx, l); err != nil {
			t.Fatal(err)
		}
		if cached := time.Since(start); cached > 10*time.Millisecond {
			t.Errorf("2回目が %v かかっている（キャッシュが効いていない）", cached)
		}

		// ランク1の語。コーパスにある語は必ず引けること。
		got, err := bank.Pick(ctx, "ฉัน", l, "")
		if err != nil {
			t.Fatal(err)
		}
		if got == nil {
			t.Fatal("ฉัน が引けない")
		}
		if got.ThaiText == "" || got.JapaneseTranslation == "" {
			t.Errorf("本文か訳が空: %+v", got)
		}
		if len(got.WordBreakdown) == 0 {
			t.Error("word_breakdown が空")
		}
		t.Logf("  %s / %s", got.ThaiText, got.JapaneseTranslation)
		if topic, _ := got.Context["topic"].(string); topic == "" {
			t.Error("context.topic が空")
		} else {
			t.Logf("  topic=%s", topic)
		}
	}
}
