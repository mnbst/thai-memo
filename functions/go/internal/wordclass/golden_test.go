package wordclass

import (
	"encoding/json"
	"os"
	"reflect"
	"testing"
)

type wordclassGolden struct {
	Single []struct {
		Word           string  `json:"word"`
		Classify       *string `json:"classify"`
		IsFunctionWord bool    `json:"is_function_word"`
	} `json:"single"`
	Multi []struct {
		Words    []string `json:"words"`
		ClassIDs []string `json:"class_ids"`
	} `json:"multi"`
	DuplicatedWords map[string][]string `json:"duplicated_words"`
	Classes         map[string]struct {
		Label        string   `json:"label"`
		FunctionWord bool     `json:"function_word"`
		Rule         string   `json:"rule"`
		Words        []string `json:"words"`
	} `json:"classes"`
}

func loadWordclassGolden(t *testing.T) *wordclassGolden {
	t.Helper()
	raw, err := os.ReadFile(
		"../../../python/scripts/daily_golden/wordclass_golden.json")
	if err != nil {
		t.Fatalf("golden の読み込みに失敗: %v", err)
	}
	var golden wordclassGolden
	if err := json.Unmarshal(raw, &golden); err != nil {
		t.Fatal(err)
	}
	return &golden
}

// TestClassifyGolden は語の分類を Python 実装と突き合わせる。
func TestClassifyGolden(t *testing.T) {
	golden := loadWordclassGolden(t)
	if len(golden.Single) == 0 {
		t.Fatal("golden が空")
	}

	var classified, unclassified, functionWords int
	for _, c := range golden.Single {
		want := ""
		if c.Classify != nil {
			want = *c.Classify
			classified++
		} else {
			unclassified++
		}
		if c.IsFunctionWord {
			functionWords++
		}

		if got := Classify(c.Word); got != want {
			t.Errorf("Classify(%q): Python=%q Go=%q", c.Word, want, got)
		}
		if got := IsFunctionWord(c.Word); got != c.IsFunctionWord {
			t.Errorf("IsFunctionWord(%q): Python=%v Go=%v",
				c.Word, c.IsFunctionWord, got)
		}
	}

	t.Logf("%d 語一致（分類あり %d / 未分類 %d、機能語 %d）",
		len(golden.Single), classified, unclassified, functionWords)
	if classified == 0 || unclassified == 0 || functionWords == 0 {
		t.Error("分類あり・未分類・機能語のどれかが踏まれていない")
	}
}

// TestClassifyAllGolden は複数語の分類（重複除去と出現順）を突き合わせる。
func TestClassifyAllGolden(t *testing.T) {
	golden := loadWordclassGolden(t)
	if len(golden.Multi) == 0 {
		t.Fatal("golden が空")
	}

	var withDuplicates, empty int
	for i, c := range golden.Multi {
		got := ClassifyAll(c.Words)

		if len(got) == 0 && len(c.ClassIDs) == 0 {
			empty++
			continue
		}
		// 同じクラスの語を複数渡したケース（重複除去が効いている）
		if len(got) < len(c.Words) {
			withDuplicates++
		}

		if !reflect.DeepEqual(got, c.ClassIDs) {
			t.Errorf("case %d: ClassifyAll(%v)\n  Python = %v\n  Go     = %v",
				i, c.Words, c.ClassIDs, got)
		}
	}

	t.Logf("%d ケース一致（重複除去あり %d / 空 %d）",
		len(golden.Multi), withDuplicates, empty)
	if withDuplicates == 0 || empty == 0 {
		t.Error("重複除去か空のどちらかが踏まれていない")
	}
}

// TestClassesDataGolden は生成した Go のデータが JSON と一致することを確かめる。
//
// classes_data.go は自動生成だが、生成スクリプトの取りこぼしを検出するため
// ラベル・ルール・語リストまで突き合わせる。
func TestClassesDataGolden(t *testing.T) {
	golden := loadWordclassGolden(t)

	if len(classes) != len(golden.Classes) {
		t.Errorf("クラス数: Python=%d Go=%d", len(golden.Classes), len(classes))
	}

	for cid, want := range golden.Classes {
		got, ok := Get(cid)
		if !ok {
			t.Errorf("クラス %s が Go 側に無い", cid)
			continue
		}
		if got.Label != want.Label {
			t.Errorf("%s.Label: Python=%q Go=%q", cid, want.Label, got.Label)
		}
		if got.FunctionWord != want.FunctionWord {
			t.Errorf("%s.FunctionWord: Python=%v Go=%v",
				cid, want.FunctionWord, got.FunctionWord)
		}
		if got.Rule != want.Rule {
			t.Errorf("%s.Rule:\n  Python=%q\n  Go    =%q", cid, want.Rule, got.Rule)
		}
		if !reflect.DeepEqual(got.Words, want.Words) {
			t.Errorf("%s.Words:\n  Python=%v\n  Go    =%v", cid, want.Words, got.Words)
		}
	}

	// 定義順（同じ語が複数クラスにあるときの優先順位）も一致していること。
	// 現状は重複語が無いので効いていないが、JSON にクラスを足したときに
	// 順序が崩れると分類が変わるため固定しておく。
	if len(golden.DuplicatedWords) == 0 {
		t.Logf("複数クラスに重複する語は無い（定義順の優先は現状効いていない）")
	}
	for word, cids := range golden.DuplicatedWords {
		if got := Classify(word); got != cids[0] {
			t.Errorf("重複語 %q: 先に定義した %s が勝つはずが %s", word, cids[0], got)
		}
	}
}
