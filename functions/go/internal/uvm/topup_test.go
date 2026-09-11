package uvm

import "testing"

// テーマで絞ると帯に数語しか残らず、セットの本数が欠けることがある
// （実測: 帯 [413,471] で 5 本頼んで 3 本）。TopUpFromBand はその穴埋め。

func cand(word string, rank int) Candidate {
	return Candidate{Word: word, Rank: rank}
}

func words(cs []Candidate) []string {
	out := make([]string, len(cs))
	for i, c := range cs {
		out[i] = c.Word
	}
	return out
}

// 埋めるのは帯の前方（ランクの大きい側＝未習の語）から。
func TestTopUpFromBandTakesForwardFirst(t *testing.T) {
	selected := []Candidate{cand("sel", 420)}
	rest := []Candidate{cand("低", 415), cand("中", 440), cand("高", 468)}

	got := TopUpFromBand(selected, rest, map[string]float64{}, 3)
	if len(got) != 3 {
		t.Fatalf("本数 %d, want 3: %v", len(got), words(got))
	}
	if got[0].Word != "sel" {
		t.Errorf("元の選出が先頭から動いている: %v", words(got))
	}
	if got[1].Word != "高" || got[2].Word != "中" {
		t.Errorf("前方から取ること: %v", words(got))
	}
}

// 未出（P=0・未登録）を先に使い、既出は足りないときだけ使う。
// 前方でも既出なら、後方の未出に譲る。
func TestTopUpFromBandPrefersUnexposed(t *testing.T) {
	selected := []Candidate{cand("sel", 420)}
	rest := []Candidate{cand("後方未出", 415), cand("前方既出", 468)}
	pMap := map[string]float64{"前方既出": 0.8}

	got := TopUpFromBand(selected, rest, pMap, 2)
	if len(got) != 2 || got[1].Word != "後方未出" {
		t.Fatalf("未出を先に使うこと: %v", words(got))
	}
}

func TestTopUpFromBandUsesExposedWhenNoneLeft(t *testing.T) {
	selected := []Candidate{cand("sel", 420)}
	rest := []Candidate{cand("既出低", 415), cand("既出高", 468)}
	pMap := map[string]float64{"既出低": 0.4, "既出高": 0.8}

	got := TopUpFromBand(selected, rest, pMap, 3)
	if len(got) != 3 {
		t.Fatalf("既出からでも埋めること: %v", words(got))
	}
	if got[1].Word != "既出高" {
		t.Errorf("既出でも前方から取ること: %v", words(got))
	}
}

// 帯を使い切っても足りないときは、あるぶんだけ返す（帯の外へは出ない）。
func TestTopUpFromBandStopsAtBandEdge(t *testing.T) {
	selected := []Candidate{cand("sel", 420)}
	rest := []Candidate{cand("唯一", 430)}

	got := TopUpFromBand(selected, rest, map[string]float64{}, 5)
	if len(got) != 2 {
		t.Fatalf("帯の外から取ってはいけない: %v", words(got))
	}
}

func TestTopUpFromBandNoShortfallKeepsSelection(t *testing.T) {
	selected := []Candidate{cand("a", 420), cand("b", 421), cand("c", 422)}
	rest := []Candidate{cand("d", 468)}

	got := TopUpFromBand(selected, rest, map[string]float64{}, 3)
	if len(got) != 3 {
		t.Fatalf("足りているのに足している: %v", words(got))
	}
}

// 呼び出し側の rest を並べ替えないこと（帯は後続の処理でも使う）。
func TestTopUpFromBandDoesNotReorderInput(t *testing.T) {
	rest := []Candidate{cand("低", 415), cand("高", 468)}
	TopUpFromBand(nil, rest, map[string]float64{}, 2)
	if rest[0].Word != "低" {
		t.Errorf("入力が並べ替えられている: %v", words(rest))
	}
}

func TestRemainingDropsSelected(t *testing.T) {
	band := []Candidate{cand("a", 1), cand("b", 2), cand("c", 3)}
	got := remaining(band, []Candidate{cand("b", 2)})
	if len(got) != 2 || got[0].Word != "a" || got[1].Word != "c" {
		t.Fatalf("selected を除くこと: %v", words(got))
	}
}
