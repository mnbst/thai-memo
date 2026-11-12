package sentence

import (
	"context"
	"math/rand"
	"strings"
	"time"

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
	// reuseSentenceLimit は 1 語あたりに読む例文の上限。置き換え済み（削除印つき）の
	// doc も猶予のあいだ同じ語に残るので、そのぶん多めに読む。
	reuseSentenceLimit = 50
	// RetiredSentenceRetention は削除印を付けた doc を物理削除するまでの猶予。
	//
	// 端末は updated_at の差分で例文を取り込むので、doc をいきなり消すと削除が
	// 伝わらず、別端末の履歴・待機列に残り続ける。印を付けて updated_at を進め、
	// 端末が読みに来る時間を置いてから消す。
	RetiredSentenceRetention = 14 * 24 * time.Hour
)

// Reuse は出し直した既出例文が置き換える元の doc。
//
// 出し直しは新しい doc を作る（端末は doc ID を主キーにしていて、同じ ID を
// 更新しても取り込み直さない）。そのままだと同じ文の doc が増え続けるので、
// 元の doc に削除印を付けて 1 文 1 doc に保つ。
type Reuse struct {
	// Replaces は同じ本文の生きている doc（削除印を付ける対象）。
	// 未読の配信 doc は含めない（待機列に載っているセットを欠けさせない）。
	Replaces []string
	// Expired は削除印を付けてから猶予を過ぎた doc（物理削除する対象）。
	Expired []string
	// Favorite は Replaces のどれかがお気に入りか。新しい doc へ引き継ぐ。
	Favorite bool
}

// sentenceDoc は例文 doc と、その ID。
type sentenceDoc struct {
	ID   string
	Data map[string]any
}

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
		cached, reuse := pickReusableDoc(docs, req.Lang, s.intn, time.Now())
		if cached == nil {
			continue
		}
		cached.KeyWord = word
		cached.GenerationTier = GenerationTier(req.UsePremiumSpec)
		out = append(out, &Produced{
			Sentence:    cached,
			TargetWords: []string{word},
			FromCache:   true,
			Reuse:       reuse,
		})
	}
	return out, nil
}

func keyWordSentenceDocs(
	ctx context.Context, db *firestore.Client, uid, word string,
) ([]sentenceDoc, error) {
	it := db.Collection("users").Doc(uid).Collection("sentences").
		Where("key_word", "==", word).Limit(reuseSentenceLimit).Documents(ctx)
	defer it.Stop()
	var out []sentenceDoc
	for {
		doc, err := it.Next()
		if err == iterator.Done {
			return out, nil
		}
		if err != nil {
			return nil, err
		}
		out = append(out, sentenceDoc{ID: doc.Ref.ID, Data: doc.Data()})
	}
}

// pickReusableDoc は例文 doc から出し直せるものをランダムに 1 つ選び、それが
// 置き換える元の doc（Reuse）と合わせて返す。
// 消した例文・訳の言語が違う例文は出さない。
func pickReusableDoc(
	docs []sentenceDoc, l lang.Lang, intn func(int) int, now time.Time,
) (*Sentence, *Reuse) {
	var ok []*Sentence
	reuse := &Reuse{}
	for _, doc := range docs {
		data := doc.Data
		if deleted, _ := data["deleted"].(bool); deleted {
			// 本人が消した例文（purged_at 無し）は端末の削除記録と突き合わせる
			// 材料なので残す。
			if at, has := data["purged_at"].(time.Time); has && now.Sub(at) >= RetiredSentenceRetention {
				reuse.Expired = append(reuse.Expired, doc.ID)
			}
			continue
		}
		if docLang, _ := data["lang"].(string); docLang != "" && docLang != string(l) {
			continue
		}
		s, err := FromMap(reusableFields(data))
		if err != nil || strings.TrimSpace(s.ThaiText) == "" || len(s.WordBreakdown) == 0 {
			continue
		}
		s.ID = doc.ID
		ok = append(ok, s)
	}
	if len(ok) == 0 {
		return nil, nil
	}
	if intn == nil {
		intn = rand.Intn
	}
	picked := ok[intn(len(ok))]
	for _, doc := range docs {
		data := doc.Data
		if deleted, _ := data["deleted"].(bool); deleted {
			continue
		}
		if text, _ := data["thai_text"].(string); strings.TrimSpace(text) != strings.TrimSpace(picked.ThaiText) {
			continue
		}
		if isUnreadDelivery(data) {
			continue
		}
		reuse.Replaces = append(reuse.Replaces, doc.ID)
		if favorite, _ := data["favorite"].(bool); favorite {
			reuse.Favorite = true
		}
	}
	// 新しい doc として保存するので、元の ID は持ち越さない。
	picked.ID = ""
	return picked, reuse
}

// isUnreadDelivery は配信したがまだ読まれていない doc か。viewed を持たない doc は
// 既読として扱う（既読を書けない版へ配信したぶん）。
func isUnreadDelivery(data map[string]any) bool {
	daily, _ := data["daily"].(bool)
	viewed, has := data["viewed"].(bool)
	return daily && has && !viewed
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
