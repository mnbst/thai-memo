// Command poolretag は GCS の例文プールの品詞を今のタガーで付け直す。
// プールの文は入ったときの品詞のまま保存されるので、タガーを直しても既存の文は変わらない。
//
// 付け直すのは確度の高い語だけ（highConfidence）。語の並びだけでは決められない語は、
// 旧ラベルのほうが正しいことがあるので触らない。手で直した文は -skip で外す。
//
// 既定は dry run。-write で <name>.bak-YYYYMMDD-HHMMSS-retag に写してから、読んだ版のまま
// 変わっていないときだけ書き戻す。
//
//	GCLOUD_PROJECT=thai-memo-prod go run ./cmd/poolretag -lang ja -skip skip_ja.json -out diff.json
//	GCLOUD_PROJECT=thai-memo-prod go run ./cmd/poolretag -lang en -tier free -labels en -skip skip_en.json -write
package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"log"
	"os"
	"reflect"
	"regexp"
	"sort"
	"time"

	"cloud.google.com/go/storage"

	"github.com/mnbst/thai-memo/functions/go/internal/lang"
	"github.com/mnbst/thai-memo/functions/go/internal/sentence"
	"github.com/mnbst/thai-memo/functions/go/internal/thainlp"
)

type change struct {
	ThaiText string `json:"thai_text"`
	Index    int    `json:"index"`
	Word     string `json:"word"`
	Meaning  string `json:"meaning"`
	Old      string `json:"old"`
	New      string `json:"new"`
}

var timeWords = map[string]bool{
	"พรุ่งนี้": true, "ตอนนี้": true, "เมื่อกี้": true, "วันนี้": true,
	"เมื่อวาน": true, "เย็นนี้": true, "คืนนี้": true, "เมื่อครู่": true,
}

var complementWords = map[string]bool{"มา": true, "อยู่": true, "ขึ้น": true, "ลง": true, "ไว้": true}

// goMeaning は ไป の語義が移動を指すか。本動詞にしてよいかの判定に使う。
var goMeaning = map[lang.Lang]*regexp.Regexp{
	lang.JA: regexp.MustCompile(`行|向|進`),
	lang.EN: regexp.MustCompile(`(?i)\bgo\b|\bgoing\b|\bhead|\btravel|\bproceed`),
	lang.KO: regexp.MustCompile(`가다|간다|가서|가는|향|나아`),
}

// bareGoMeaning は ไป の語義が「行く」だけか。これは本動詞の可能性が高いので助動詞にしない。
var bareGoMeaning = map[lang.Lang]*regexp.Regexp{
	lang.JA: regexp.MustCompile(`行く$`),
	lang.EN: regexp.MustCompile(`(?i)\bgo$`),
	lang.KO: regexp.MustCompile(`가다$`),
}

// highConfidence は tag（日本語ラベル）への付け直しを採用してよいか。
// 2026-11-06 の抜き取りで、これ以外は約3割が悪くなった。
func highConfidence(word, meaning, tag string, l lang.Lang) bool {
	switch {
	case timeWords[word]:
		return tag == "名詞"
	case word == "ของ" || word == "ที่" || word == "เสร็จ":
		return true
	case word == "ไป" && tag == "動詞":
		return goMeaning[l].MatchString(meaning)
	case word == "ไป" && tag == "助動詞":
		return !bareGoMeaning[l].MatchString(meaning)
	case complementWords[word]:
		return tag == "助動詞"
	case tag == "類別詞":
		// 名詞＋類別詞＋指示語・数詞＋類別詞の並びだけで付くので、並びが合えば類別詞で確定する。
		return true
	case word == "ฉัน" && tag == "動詞":
		// ฉันเพล 等、僧侶の食事の語が続くときだけ付く。
		return true
	case fixedPOSWords[word]:
		return true
	}
	return false
}

// fixedPOSWords は pos_override で品詞を固定した語のうち、旧タガーが誤っていたもの（2026-11-08）。
var fixedPOSWords = map[string]bool{
	"ทัวร์": true, "เหนือกว่า": true, "บอกว่า": true, "บทลงโทษ": true, "ไม่ต้องการ": true,
	"แน่ๆ": true, "วันเกิด": true, "คลิป": true, "เป็นมิตร": true, "พื้นบ้าน": true,
}

// retag は pool の品詞を確度の高い語だけ書き換え、変えた語を返す。
func retag(pool []sentence.Sentence, skip map[string]bool, l, labels lang.Lang) ([]change, error) {
	changes := []change{}
	for n := range pool {
		s := &pool[n]
		if skip[s.ThaiText] {
			continue
		}
		words := make([]string, len(s.WordBreakdown))
		for i, w := range s.WordBreakdown {
			words[i] = w.Word
		}
		tags, err := thainlp.TagWords(words)
		if err != nil {
			return nil, fmt.Errorf("%s: %w", s.ThaiText, err)
		}
		for i := range s.WordBreakdown {
			w := &s.WordBreakdown[i]
			tag, ok := tags[i]
			if !ok || w.Word == "" {
				continue
			}
			label := thainlp.LocalizePOS(tag, labels)
			if label == w.GrammaticalRole || !highConfidence(w.Word, w.Meaning, tag, l) {
				continue
			}
			changes = append(changes, change{s.ThaiText, i, w.Word, w.Meaning, w.GrammaticalRole, label})
			w.GrammaticalRole = label
		}
	}
	return changes, nil
}

// sameJSON は 2 つの JSON が同じ内容か。型に無い項目が書き戻しで落ちないことを確かめる。
func sameJSON(a, b []byte) (bool, error) {
	var x, y any
	if err := json.Unmarshal(a, &x); err != nil {
		return false, err
	}
	if err := json.Unmarshal(b, &y); err != nil {
		return false, err
	}
	return reflect.DeepEqual(x, y), nil
}

func main() {
	langCode := flag.String("lang", "ja", "プールの言語（ja / en / ko）")
	tier := flag.String("tier", "premium", "プールのティア（premium / free）")
	labels := flag.String("labels", "ja", "ファイルの品詞ラベルの言語（free_pool_en だけ en）")
	skipPath := flag.String("skip", "", "付け直さない文（thai_text の JSON 配列）")
	out := flag.String("out", "", "変える語を書き出す JSON")
	write := flag.Bool("write", false, "GCS へ書き戻す（バックアップを取ってから）")
	flag.Parse()

	l, ok := lang.Parse(*langCode)
	if !ok {
		log.Fatalf("-lang %q は不明", *langCode)
	}
	labelLang, ok := lang.Parse(*labels)
	if !ok {
		log.Fatalf("-labels %q は不明", *labels)
	}
	skip := map[string]bool{}
	if *skipPath != "" {
		raw, err := os.ReadFile(*skipPath)
		if err != nil {
			log.Fatal(err)
		}
		var texts []string
		if err := json.Unmarshal(raw, &texts); err != nil {
			log.Fatal(err)
		}
		for _, t := range texts {
			skip[t] = true
		}
	}
	project := os.Getenv("GCLOUD_PROJECT")
	if project == "" {
		log.Fatal("GCLOUD_PROJECT が未設定")
	}

	ctx := context.Background()
	client, err := storage.NewClient(ctx)
	if err != nil {
		log.Fatal(err)
	}
	defer client.Close()
	bucket := client.Bucket(project + "-uvm-data")
	name := sentence.PoolObjectFor(*tier, l)
	obj := bucket.Object(name)
	attrs, err := obj.Attrs(ctx)
	if err != nil {
		log.Fatal(err)
	}
	r, err := obj.Generation(attrs.Generation).NewReader(ctx)
	if err != nil {
		log.Fatal(err)
	}
	raw, err := io.ReadAll(r)
	r.Close()
	if err != nil {
		log.Fatal(err)
	}
	var pool []sentence.Sentence
	if err := json.Unmarshal(raw, &pool); err != nil {
		log.Fatal(err)
	}
	// 付け直す前に、読み書きだけで内容が変わらないことを確かめる。
	before, err := json.Marshal(pool)
	if err != nil {
		log.Fatal(err)
	}
	if same, err := sameJSON(raw, before); err != nil || !same {
		log.Fatalf("%s は読み書きで内容が変わる（書き戻さない）: %v", name, err)
	}

	changes, err := retag(pool, skip, l, labelLang)
	if err != nil {
		log.Fatal(err)
	}
	sentences := map[string]bool{}
	counts := map[string]int{}
	for _, c := range changes {
		sentences[c.ThaiText] = true
		counts[c.Word+" "+c.Old+"→"+c.New]++
	}
	fmt.Printf("%s: %d文のうち %d文・%d語を変える（除外 %d文）\n", name, len(pool), len(sentences), len(changes), len(skip))
	keys := make([]string, 0, len(counts))
	for k := range counts {
		keys = append(keys, k)
	}
	sort.Slice(keys, func(i, j int) bool { return counts[keys[i]] > counts[keys[j]] })
	for i, k := range keys {
		if i == 15 {
			break
		}
		fmt.Printf("%6d  %s\n", counts[k], k)
	}
	if *out != "" {
		b, err := json.MarshalIndent(changes, "", " ")
		if err != nil {
			log.Fatal(err)
		}
		if err := os.WriteFile(*out, b, 0o644); err != nil {
			log.Fatal(err)
		}
	}
	if !*write || len(changes) == 0 {
		return
	}

	backup := fmt.Sprintf("%s.bak-%s-retag", name, time.Now().Format("20060102-150405"))
	if _, err := bucket.Object(backup).CopierFrom(obj.Generation(attrs.Generation)).Run(ctx); err != nil {
		log.Fatalf("バックアップに失敗（書き戻さない）: %v", err)
	}
	data, err := json.Marshal(pool)
	if err != nil {
		log.Fatal(err)
	}
	w := obj.If(storage.Conditions{GenerationMatch: attrs.Generation}).NewWriter(ctx)
	w.ContentType = "application/json"
	if _, err := w.Write(data); err != nil {
		w.Close()
		log.Fatal(err)
	}
	if err := w.Close(); err != nil {
		log.Fatalf("書き戻しに失敗（読んだ後に別の処理が書いた可能性）: %v", err)
	}
	fmt.Printf("書き戻した（バックアップ: %s）\n", backup)
}
