package uvm

import "testing"

// 帯の中で 5 本に届かないことがある（実測: 帯 [413,471] で 5 本頼んで 3 本、
// 帯の未出が尽きた premium ユーザーで 1 本）。TopUpFromBand はその穴埋め。
// 帯の中は低ランク（易しい側）優先、足りなければ帯の外・前方（高ランク）へ
// 帯に近い順で広げる。

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

// 帯の中はランクの小さい側（易しい語）から埋める。
func TestTopUpFromBandTakesLowRankFirst(t *testing.T) {
	selected := []Candidate{cand("sel", 420)}
	rest := []Candidate{cand("低", 415), cand("中", 440), cand("高", 468)}

	got := TopUpFromBand(selected, rest, nil, map[string]float64{}, 3)
	if len(got) != 3 {
		t.Fatalf("本数 %d, want 3: %v", len(got), words(got))
	}
	if got[0].Word != "sel" {
		t.Errorf("元の選出が先頭から動いている: %v", words(got))
	}
	if got[1].Word != "低" || got[2].Word != "中" {
		t.Errorf("帯の中は低ランクから取ること: %v", words(got))
	}
}

// 未出（P=0・未登録）を先に使い、既出は足りないときだけ使う。
// 低ランクでも既出なら、高ランクの未出に譲る。
func TestTopUpFromBandPrefersUnexposed(t *testing.T) {
	selected := []Candidate{cand("sel", 420)}
	rest := []Candidate{cand("低ランク既出", 415), cand("高ランク未出", 468)}
	pMap := map[string]float64{"低ランク既出": 0.8}

	got := TopUpFromBand(selected, rest, nil, pMap, 2)
	if len(got) != 2 || got[1].Word != "高ランク未出" {
		t.Fatalf("未出を先に使うこと: %v", words(got))
	}
}

func TestTopUpFromBandUsesExposedWhenNoneLeft(t *testing.T) {
	selected := []Candidate{cand("sel", 420)}
	rest := []Candidate{cand("既出低", 415), cand("既出高", 468)}
	pMap := map[string]float64{"既出低": 0.4, "既出高": 0.8}

	got := TopUpFromBand(selected, rest, nil, pMap, 3)
	if len(got) != 3 {
		t.Fatalf("既出からでも埋めること: %v", words(got))
	}
	if got[1].Word != "既出低" {
		t.Errorf("既出でも帯の中は低ランクから取ること: %v", words(got))
	}
}

// 前方ぶんを渡さなければ帯の外へは出ない（あるぶんだけ返す）。
func TestTopUpFromBandStopsAtBandEdge(t *testing.T) {
	selected := []Candidate{cand("sel", 420)}
	rest := []Candidate{cand("唯一", 430)}

	got := TopUpFromBand(selected, rest, nil, map[string]float64{}, 5)
	if len(got) != 2 {
		t.Fatalf("帯の外から取ってはいけない: %v", words(got))
	}
}

func TestTopUpFromBandNoShortfallKeepsSelection(t *testing.T) {
	selected := []Candidate{cand("a", 420), cand("b", 421), cand("c", 422)}
	rest := []Candidate{cand("d", 468)}

	got := TopUpFromBand(selected, rest, nil, map[string]float64{}, 3)
	if len(got) != 3 {
		t.Fatalf("足りているのに足している: %v", words(got))
	}
}

// 呼び出し側の rest を並べ替えないこと（帯は後続の処理でも使う）。
func TestTopUpFromBandDoesNotReorderInput(t *testing.T) {
	rest := []Candidate{cand("低", 415), cand("高", 468)}
	TopUpFromBand(nil, rest, nil, map[string]float64{}, 2)
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

// テーマ無し（premium おまかせ）で帯の未出語が尽きかけている場合。
// SelectWeighted は zeroP の数しか返さないので、そこから帯の残りで埋める。
// prod 2026-09-12 に帯59語・未出1語のユーザーが1本しか受け取れなかった形。
func TestTopUpFromBandFillsWhenUnexposedRunsOut(t *testing.T) {
	band := []Candidate{
		cand("既出1", 415), cand("既出2", 440),
		cand("既出3", 455), cand("既出4", 468), cand("未出", 473),
	}
	pMap := map[string]float64{"既出1": 0.4, "既出2": 0.5, "既出3": 0.6, "既出4": 0.8}

	// zeroP は1語だけ。テーマで絞っていないので candidates == band。
	selected := []Candidate{cand("未出", 473)}
	got := TopUpFromBand(selected, remaining(band, selected), nil, pMap, 5)

	if len(got) != 5 {
		t.Fatalf("本数 %d, want 5: %v", len(got), words(got))
	}
	if got[0].Word != "未出" {
		t.Errorf("未出が先頭に残ること: %v", words(got))
	}
	seen := map[string]bool{}
	for _, c := range got {
		if seen[c.Word] {
			t.Fatalf("同じ語を二度使っている: %v", words(got))
		}
		seen[c.Word] = true
	}
}

// 帯の中で埋まらないときは前方（帯の外・ランクの大きい側）の未出を使う。
// 帯の既出より前方の未出が先で、前方は帯に近い側から取る。
func TestTopUpFromBandUsesForwardBeforeExposed(t *testing.T) {
	selected := []Candidate{cand("未出", 473)}
	rest := []Candidate{cand("帯既出", 468)}
	forward := []Candidate{cand("前方遠い", 500), cand("前方近い", 474), cand("前方既出", 480)}
	pMap := map[string]float64{"帯既出": 0.8, "前方既出": 0.6}

	got := TopUpFromBand(selected, rest, forward, pMap, 3)
	if len(got) != 3 {
		t.Fatalf("本数 %d, want 3: %v", len(got), words(got))
	}
	if got[1].Word != "前方近い" || got[2].Word != "前方遠い" {
		t.Fatalf("前方の未出を帯に近い側から使うこと: %v", words(got))
	}
}

// 前方も未出が尽きたら、最後の手段として帯の既出で埋める。
func TestTopUpFromBandFallsBackToExposed(t *testing.T) {
	selected := []Candidate{cand("未出", 473)}
	rest := []Candidate{cand("帯既出低", 415), cand("帯既出高", 468)}
	forward := []Candidate{cand("前方既出", 474)}
	pMap := map[string]float64{"帯既出低": 0.4, "帯既出高": 0.8, "前方既出": 0.6}

	got := TopUpFromBand(selected, rest, forward, pMap, 3)
	if len(got) != 3 {
		t.Fatalf("本数 %d, want 3: %v", len(got), words(got))
	}
	if got[1].Word != "帯既出低" || got[2].Word != "帯既出高" {
		t.Fatalf("既出も帯の中は低ランクから使うこと: %v", words(got))
	}
}
