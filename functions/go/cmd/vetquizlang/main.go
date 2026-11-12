// Command vetquizlang は Firestore のクイズ解説キャッシュを走査し、
// 解説・ダミー理由が指定と違う言語で書かれた件を洗い出す。
//
// 対象は -collection で選ぶ。
//   - quiz_questions（既定）: 穴埋め。(lang, thai_text) 単位
//   - word_explanations: 意味4択の解説。(lang, word, meaning) 単位
//
// どちらも言語別のキーで全ユーザー共有・TTL 無しなので、
// 1回のドリフトがその例文を受け取る全員に配られ続ける（SRS で1人あたり
// 最大5回）。生成側の検査（internal/gemini/repair.go）はこれから作る分に
// しか効かないため、既存分はここで消して作り直させる。
//
//	# 数えるだけ（既定）
//	GOOGLE_CLOUD_PROJECT=thai-memo-prod go run ./cmd/vetquizlang -out /tmp/quizlang.json
//
//	# 消す。消したキーは次の出題で作り直される（Load がキャッシュミス扱い）
//	GOOGLE_CLOUD_PROJECT=thai-memo-prod go run ./cmd/vetquizlang -delete
//
//	# 意味4択の解説キャッシュ
//	GOOGLE_CLOUD_PROJECT=thai-memo-prod go run ./cmd/vetquizlang -collection word_explanations
//
// 判定はランタイムと同じ lang.IsWrongLanguage。ここだけ基準がずれると、
// 消した端から同じものが書き戻る。
package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"os"
	"strings"

	"cloud.google.com/go/firestore"
	"github.com/mnbst/thai-memo/functions/go/internal/fbapp"
	"github.com/mnbst/thai-memo/functions/go/internal/lang"
	"google.golang.org/api/iterator"
)

// 走査できるコレクション。quiz_cloze_cache.go / word_explanation_cache.go の名前。
const (
	clozeCollection   = "quiz_questions"
	meaningCollection = "word_explanations"
)

// collection は -collection で選んだ走査対象。
var collection = clozeCollection

// entry は quizClozeEntry / wordExplanationEntry のうち言語を見る項目。
// あちらは package main なので import できず、ここに持つ。
// コレクションに無い項目は空のまま読まれる。
type entry struct {
	Lang          string   `firestore:"lang"`
	ThaiText      string   `firestore:"thai_text"`
	CorrectAnswer string   `firestore:"correct_answer"`
	Word          string   `firestore:"word"`
	Meaning       string   `firestore:"meaning"`
	Explanation   string   `firestore:"explanation"`
	DummyReasons  []string `firestore:"dummy_reasons"`
}

// finding は言語がずれた1件。
type finding struct {
	Key           string   `json:"key"`
	Lang          string   `json:"lang"`
	ThaiText      string   `json:"thai_text,omitempty"`
	CorrectAnswer string   `json:"correct_answer,omitempty"`
	Word          string   `json:"word,omitempty"`
	Meaning       string   `json:"meaning,omitempty"`
	Fields        []string `json:"fields"`
	Explanation   string   `json:"explanation"`
	DummyReasons  []string `json:"dummy_reasons"`
}

func main() {
	out := flag.String("out", "", "見つけた件を書き出す JSON ファイル")
	del := flag.Bool("delete", false, "見つけた件を消す（既定は数えるだけ）")
	limit := flag.Int("limit", 0, "走査する件数の上限（0 で全件）")
	keys := flag.String("keys", "",
		"消すキーをカンマ区切りで名指しする。走査せず、このキーだけ消す")
	coll := flag.String("collection", clozeCollection,
		"走査するコレクション（quiz_questions / word_explanations）")
	flag.Parse()
	if *coll != clozeCollection && *coll != meaningCollection {
		log.Fatalf("-collection は %s か %s", clozeCollection, meaningCollection)
	}
	collection = *coll

	ctx := context.Background()
	if fbapp.ProjectID() == "" {
		log.Fatal("GOOGLE_CLOUD_PROJECT が空。対象プロジェクトを指定する")
	}
	db, err := fbapp.Firestore(ctx)
	if err != nil {
		log.Fatal(err)
	}
	defer db.Close()

	// 名指しの削除。走査の結果をそのまま消すより、消す対象が目で見えている
	// ぶん確実なので、件数が少ないときはこちらを使う。
	if *keys != "" {
		named := splitKeys(*keys)
		if err := removeKeys(ctx, db, named); err != nil {
			log.Fatal(err)
		}
		fmt.Printf("%d 件消した。次の出題で作り直される\n", len(named))
		return
	}

	findings, scanned, err := scan(ctx, db, *limit)
	if err != nil {
		log.Fatal(err)
	}

	report(findings, scanned)
	if *out != "" {
		if err := writeJSON(*out, findings); err != nil {
			log.Fatal(err)
		}
		fmt.Printf("詳細を %s に書いた\n", *out)
	}
	if !*del || len(findings) == 0 {
		return
	}
	if err := remove(ctx, db, findings); err != nil {
		log.Fatal(err)
	}
	fmt.Printf("%d 件消した。次の出題で作り直される\n", len(findings))
}

func scan(
	ctx context.Context, db *firestore.Client, limit int,
) (findings []finding, scanned int, err error) {
	iter := db.Collection(collection).Documents(ctx)
	defer iter.Stop()

	for limit == 0 || scanned < limit {
		doc, err := iter.Next()
		if err == iterator.Done {
			break
		}
		if err != nil {
			return nil, scanned, err
		}
		scanned++

		var e entry
		if err := doc.DataTo(&e); err != nil {
			// 読めない1件で棚卸しを止めない。
			log.Printf("読めないドキュメント key=%s error=%v", doc.Ref.ID, err)
			continue
		}
		if fields := driftedFields(e); len(fields) > 0 {
			findings = append(findings, finding{
				Key:           doc.Ref.ID,
				Lang:          e.Lang,
				ThaiText:      e.ThaiText,
				CorrectAnswer: e.CorrectAnswer,
				Word:          e.Word,
				Meaning:       e.Meaning,
				Fields:        fields,
				Explanation:   e.Explanation,
				DummyReasons:  e.DummyReasons,
			})
		}
	}
	return findings, scanned, nil
}

// driftedFields は言語がずれている項目名を返す。
// lang が空のエントリは既定（ja）として見る。
func driftedFields(e entry) []string {
	l := lang.Resolve(e.Lang)

	var fields []string
	if lang.IsWrongLanguage(e.Explanation, l) {
		fields = append(fields, "explanation")
	}
	if lang.AnyWrongLanguage(l, e.DummyReasons...) {
		fields = append(fields, "dummy_reasons")
	}
	return fields
}

func report(findings []finding, scanned int) {
	byLang := map[string]int{}
	byField := map[string]int{}
	for _, f := range findings {
		byLang[f.Lang]++
		for _, field := range f.Fields {
			byField[field]++
		}
	}

	fmt.Printf("%s: %d 件を走査、%d 件が指定と違う言語\n",
		collection, scanned, len(findings))
	for l, n := range byLang {
		fmt.Printf("  lang=%s: %d 件\n", l, n)
	}
	for field, n := range byField {
		fmt.Printf("  %s: %d 件\n", field, n)
	}

	// 中身を見ないと直ったかどうか判断できないので、先頭だけ出す。
	for i, f := range findings {
		if i >= 5 {
			fmt.Printf("  ...ほか %d 件\n", len(findings)-5)
			break
		}
		subject := f.ThaiText
		if subject == "" {
			subject = f.Word + "（" + f.Meaning + "）"
		}
		fmt.Printf("  - %s / %s / %q\n", f.Key, subject, f.Explanation)
	}
}

func remove(ctx context.Context, db *firestore.Client, findings []finding) error {
	keys := make([]string, 0, len(findings))
	for _, f := range findings {
		keys = append(keys, f.Key)
	}
	return removeKeys(ctx, db, keys)
}

// removeKeys はキーを名指しで消す。消えたキーは Load がキャッシュミス扱いに
// するので、次の出題で作り直される。
func removeKeys(ctx context.Context, db *firestore.Client, keys []string) error {
	for _, key := range keys {
		if _, err := db.Collection(collection).Doc(key).Delete(ctx); err != nil {
			return fmt.Errorf("key=%s: %w", key, err)
		}
		fmt.Printf("消した: %s\n", key)
	}
	return nil
}

func splitKeys(raw string) []string {
	var keys []string
	for _, key := range strings.Split(raw, ",") {
		if key = strings.TrimSpace(key); key != "" {
			keys = append(keys, key)
		}
	}
	return keys
}

func writeJSON(path string, findings []finding) error {
	data, err := json.MarshalIndent(findings, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(path, append(data, '\n'), 0o644)
}
