package sentence

import (
	"context"
	"math/rand"
	"strings"

	"cloud.google.com/go/firestore"
	"google.golang.org/api/iterator"

	"github.com/mnbst/thai-memo/functions/go/internal/lang"
	"github.com/mnbst/thai-memo/functions/go/internal/uvm"
)

const (
	// MinSetSize はセットの最低本数。1本だとまとめクイズが出ない（BeginnerMinSetSize）。
	MinSetSize = BeginnerMinSetSize
	// reuseWordLimit は既出例文を探す語数の上限。例文が見つからない語が続いても
	// 読み取りが増えすぎないようにする。
	reuseWordLimit = 10
	// reuseSentenceLimit は 1 語あたりに読む例文の上限。
	reuseSentenceLimit = 20
)

// unseenWordSelector は未出語だけの選定と既出例文の取り出しができる WordSelector。
// 実装は TargetWordSelector。
type unseenWordSelector interface {
	WordSelector
	SelectUnseenTargetWords(
		ctx context.Context, db *firestore.Client, freqRank uvm.FreqRank,
		uid string, params map[string]any,
		maxVocab *int, count int, isPremium bool, estimatedVocab *int,
		testedVocab int,
	) ([]TargetWord, error)
	PickReused(
		ctx context.Context, db *firestore.Client, freqRank uvm.FreqRank,
		req ProduceRequest, count int, skip map[string]bool,
	) ([]*Produced, error)
}

// PickReused は帯の既出語から count 本ぶん、本人の過去の例文を選ぶ。skip の語は使わない。
// LLM は呼ばないので生成の失敗に左右されない。
func (s *TargetWordSelector) PickReused(
	ctx context.Context, db *firestore.Client, freqRank uvm.FreqRank,
	req ProduceRequest, count int, skip map[string]bool,
) ([]*Produced, error) {
	var maxVocab *int
	if !req.UsePremiumSpec {
		v := uvm.FreeTierMaxVocab
		maxVocab = &v
	}
	words, err := s.Session.ReusableWords(ctx, db, freqRank, uvm.SessionRequest{
		UID:            req.UID,
		MaxVocab:       maxVocab,
		EstimatedVocab: &req.EstimatedVocab,
		TestedVocab:    req.TestedVocab,
	})
	if err != nil {
		return nil, err
	}

	var out []*Produced
	tried := 0
	for _, word := range words {
		if len(out) >= count || tried >= reuseWordLimit {
			break
		}
		if skip[word] {
			continue
		}
		tried++
		docs, err := keyWordSentenceDocs(ctx, db, req.UID, word)
		if err != nil {
			return out, err
		}
		cached := pickReusableDoc(docs, req.Lang, s.intn)
		if cached == nil {
			continue
		}
		cached.KeyWord = word
		cached.GenerationTier = GenerationTier(req.UsePremiumSpec)
		out = append(out, &Produced{
			Sentence:    cached,
			TargetWords: []string{word},
			FromCache:   true,
		})
	}
	return out, nil
}

func keyWordSentenceDocs(
	ctx context.Context, db *firestore.Client, uid, word string,
) ([]map[string]any, error) {
	it := db.Collection("users").Doc(uid).Collection("sentences").
		Where("key_word", "==", word).Limit(reuseSentenceLimit).Documents(ctx)
	defer it.Stop()
	var out []map[string]any
	for {
		doc, err := it.Next()
		if err == iterator.Done {
			return out, nil
		}
		if err != nil {
			return nil, err
		}
		out = append(out, doc.Data())
	}
}

// pickReusableDoc は例文 doc から出し直せるものをランダムに 1 つ選ぶ。
// 消した例文・訳の言語が違う例文は出さない。
func pickReusableDoc(docs []map[string]any, l lang.Lang, intn func(int) int) *Sentence {
	var ok []*Sentence
	for _, data := range docs {
		if deleted, _ := data["deleted"].(bool); deleted {
			continue
		}
		if docLang, _ := data["lang"].(string); docLang != "" && docLang != string(l) {
			continue
		}
		s, err := FromMap(reusableFields(data))
		if err != nil || strings.TrimSpace(s.ThaiText) == "" || len(s.WordBreakdown) == 0 {
			continue
		}
		ok = append(ok, s)
	}
	if len(ok) == 0 {
		return nil
	}
	if intn == nil {
		intn = rand.Intn
	}
	return ok[intn(len(ok))]
}

// reusableFields は例文の本文だけを取り出す（既読・お気に入り・セットの情報は持ち越さない）。
func reusableFields(data map[string]any) map[string]any {
	out := map[string]any{}
	for _, key := range []string{
		"thai_text", "pronunciation", "japanese_translation",
		"word_breakdown", "context", "scene", "shot_id",
	} {
		if v, ok := data[key]; ok {
			out[key] = v
		}
	}
	return out
}
