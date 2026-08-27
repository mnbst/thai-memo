package sentence

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"math/rand"
	"sync"

	"cloud.google.com/go/storage"

	"github.com/mnbst/thai-memo/functions/go/internal/lang"
)

// FreeBank は事前生成済みの free 例文バンク（GCS）。
//
// バンクは scripts/build_free_sentence_bank.py で言語ごとに作る。
// まだ無い言語（アップロード前・新言語の追加直後）は空で、呼び出し側が
// LLM 生成へ落ちる。
type FreeBank struct {
	// ProjectID は GCS バケット名 {ProjectID}-uvm-data に使う。
	ProjectID string
	// Rand は抽選に使う。nil なら共有の乱数源。テストで固定する。
	Rand *rand.Rand

	mu    sync.Mutex
	cache map[lang.Lang][]Sentence
}

// Sentences は GCS から free_sentences_<lang>.json を読み込みキャッシュする
// （sentence_service.py:get_free_sentences:224）。
//
// ja だけは旧ファイル名 free_sentences.json にも退避する（新バンクを上げる前に
// デプロイしても free が止まらないため）。見つからなければ空を返し、それも
// キャッシュする（毎回 GCS を叩かない）。
func (b *FreeBank) Sentences(ctx context.Context, l lang.Lang) ([]Sentence, error) {
	b.mu.Lock()
	defer b.mu.Unlock()
	if cached, ok := b.cache[l]; ok {
		return cached, nil
	}

	names := []string{fmt.Sprintf("free_sentences_%s.json", l)}
	if l == lang.JA {
		names = append(names, "free_sentences.json")
	}

	client, err := storage.NewClient(ctx)
	if err != nil {
		return nil, fmt.Errorf("GCS クライアントの生成に失敗: %w", err)
	}
	defer client.Close()
	bucket := client.Bucket(b.ProjectID + "-uvm-data")

	var sentences []Sentence
	found := false
	for _, name := range names {
		r, err := bucket.Object(name).NewReader(ctx)
		if err != nil {
			// Python は blob.exists() で分岐する。開けない理由は問わない。
			continue
		}
		data, err := io.ReadAll(r)
		r.Close()
		if err != nil {
			return nil, fmt.Errorf("%s の読み出しに失敗: %w", name, err)
		}
		if err := json.Unmarshal(data, &sentences); err != nil {
			return nil, fmt.Errorf("%s の JSON 解析に失敗: %w", name, err)
		}
		found = true
		break
	}
	if !found {
		log.Printf("free bank missing for lang=%s; falling back to LLM", l)
	}

	if b.cache == nil {
		b.cache = map[lang.Lang][]Sentence{}
	}
	b.cache[l] = sentences
	return sentences, nil
}

// Pick は target_word に一致する free 例文をランダムに 1 件返す
// （sentence_service.py:pick_free_sentence:253）。
//
// topic を渡すとそのテーマの文を優先するが、無ければテーマを無視して選ぶ。
// バンクは key_word × テーマの全組み合わせを持たないので、一致が無いときに
// 諦めると配信が落ちる。一致が 1 件も無ければ nil（LLM 生成へ落ちる）。
func (b *FreeBank) Pick(ctx context.Context, targetWord string, l lang.Lang, topic string) (*Sentence, error) {
	sentences, err := b.Sentences(ctx, l)
	if err != nil {
		return nil, err
	}
	var candidates []Sentence
	for _, s := range sentences {
		if s.KeyWord == targetWord {
			candidates = append(candidates, s)
		}
	}
	if len(candidates) == 0 {
		return nil, nil
	}
	if topic != "" {
		var sameTopic []Sentence
		for _, s := range candidates {
			if t, _ := s.Context["topic"].(string); t == topic {
				sameTopic = append(sameTopic, s)
			}
		}
		if len(sameTopic) > 0 {
			candidates = sameTopic
		}
	}

	// バンクはプロセス内でキャッシュしているので、返す前にコピーする
	// （呼び出し側が generation_tier 等を足してもバンクを汚さない）。
	picked := candidates[b.intn(len(candidates))]
	picked.WordBreakdown = append([]Word(nil), picked.WordBreakdown...)
	picked.Context = LocalizeContext(picked.Context, l)
	return &picked, nil
}

func (b *FreeBank) intn(n int) int {
	if b.Rand != nil {
		return b.Rand.Intn(n)
	}
	return rand.Intn(n)
}
