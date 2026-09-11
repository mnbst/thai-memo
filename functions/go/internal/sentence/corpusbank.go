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

// CorpusBank は静的コーパス（GCS）。全ティア共通の例文の出どころ。
//
// FreeBank と同じ「事前に作った文を key_word とテーマで引く」仕組みだが、
// 範囲が違う。FreeBank は free ユーザーぶんだけの穴埋めで、当たらなければ
// LLM 生成へ落ちるのが前提だった。こちらはランク 3464 までの全語を持ち、
// 通常の学習帯はまず当たる。当たらないのは帯がコーパスの外へ出たときで、
// そのときだけ LLM 生成へ落ちる。
//
// ファイルは言語ごと（corpus_sentences_ja.json / _en.json）。一文二訳なので
// タイ語本文は両方に同じものが入り、訳と語義だけが違う。
// scripts/export_corpus_bank.py が書き出す。
type CorpusBank struct {
	// ProjectID は GCS バケット名 {ProjectID}-uvm-data に使う。
	ProjectID string
	// Rand は抽選に使う。nil なら共有の乱数源。テストで固定する。
	Rand *rand.Rand

	mu sync.Mutex
	// index は言語ごとの key_word → 例文。読み込み時に1度だけ組む。
	// 13,000 本を毎回なめるより、インスタンスの寿命で見て安い。
	index map[lang.Lang]map[string][]Sentence
}

// Load は corpus_sentences_<lang>.json を読んで key_word で索く形にする。
//
// 見つからなければ空を返し、それもキャッシュする（毎回 GCS を叩かない）。
// 空のときは呼び出し側が LLM 生成へ落ちるので、バンクを上げる前に
// デプロイしても止まらない。
func (b *CorpusBank) Load(ctx context.Context, l lang.Lang) (map[string][]Sentence, error) {
	b.mu.Lock()
	defer b.mu.Unlock()
	if cached, ok := b.index[l]; ok {
		return cached, nil
	}

	name := fmt.Sprintf("corpus_sentences_%s.json", l)
	index := map[string][]Sentence{}

	client, err := storage.NewClient(ctx)
	if err != nil {
		return nil, fmt.Errorf("GCS クライアントの生成に失敗: %w", err)
	}
	defer client.Close()

	r, err := client.Bucket(b.ProjectID + "-uvm-data").Object(name).NewReader(ctx)
	if err != nil {
		log.Printf("corpus bank missing for lang=%s; falling back to LLM", l)
	} else {
		data, readErr := io.ReadAll(r)
		r.Close()
		if readErr != nil {
			return nil, fmt.Errorf("%s の読み出しに失敗: %w", name, readErr)
		}
		var sentences []Sentence
		if err := json.Unmarshal(data, &sentences); err != nil {
			return nil, fmt.Errorf("%s の JSON 解析に失敗: %w", name, err)
		}
		for _, s := range sentences {
			index[s.KeyWord] = append(index[s.KeyWord], s)
		}
		log.Printf("corpus bank loaded: lang=%s sentences=%d words=%d",
			l, len(sentences), len(index))
	}

	if b.index == nil {
		b.index = map[lang.Lang]map[string][]Sentence{}
	}
	b.index[l] = index
	return index, nil
}

// Pick は target_word の例文を1件返す。無ければ nil（LLM 生成へ落ちる）。
//
// topic を渡すとそのテーマを優先するが、無ければテーマを無視して選ぶ。
// コーパスは語ごとに平均4.5テーマしか持たないので、一致が無いときに諦めると
// テーマ指定のたびに LLM を呼ぶことになる。
func (b *CorpusBank) Pick(
	ctx context.Context, targetWord string, l lang.Lang, topic string,
) (*Sentence, error) {
	index, err := b.Load(ctx, l)
	if err != nil {
		return nil, err
	}
	candidates := index[targetWord]
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

func (b *CorpusBank) intn(n int) int {
	if b.Rand != nil {
		return b.Rand.Intn(n)
	}
	return rand.Intn(n)
}
