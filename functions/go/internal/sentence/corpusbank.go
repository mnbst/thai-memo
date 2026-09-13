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
//
// これに加えて、運用中に LLM 生成された例文のうち judge を通ったものを
// 貯めたプール（corpus_pool_<lang>.json、dailyBatch が毎日書き出す）も
// 同じ索引へ重ねる。静的コーパスは語×テーマで1本しか持たないので、
// 同じ key_word が再選出された人に同じ文が出る。プールはその穴を
// 埋める在庫で、出どころが違うだけで扱いは静的コーパスと同じ。
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

// Load は corpus_sentences_<lang>.json とプール（corpus_pool_<lang>.json）を
// 読んで key_word で索く形にする。
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

	index := map[string][]Sentence{}

	client, err := storage.NewClient(ctx)
	if err != nil {
		return nil, fmt.Errorf("GCS クライアントの生成に失敗: %w", err)
	}
	defer client.Close()
	bucket := client.Bucket(b.ProjectID + "-uvm-data")

	for _, name := range []string{CorpusObject(l), PoolObject(l)} {
		sentences, err := ReadSentences(ctx, bucket, name)
		if err != nil {
			return nil, err
		}
		if sentences == nil {
			// 静的コーパス・プールのどちらも、無ければ無いまま進む。
			// プールは運用が始まるまで存在しない。
			log.Printf("corpus bank: %s missing for lang=%s", name, l)
			continue
		}
		for _, s := range sentences {
			index[s.KeyWord] = append(index[s.KeyWord], s)
		}
		log.Printf("corpus bank loaded: object=%s lang=%s sentences=%d words=%d",
			name, l, len(sentences), len(index))
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

// CorpusObject / PoolObject は静的コーパスとプールの GCS オブジェクト名。
// dailyBatch の書き出し側と読み込み側で名前がずれないよう、ここで一元化する。
func CorpusObject(l lang.Lang) string { return fmt.Sprintf("corpus_sentences_%s.json", l) }
func PoolObject(l lang.Lang) string   { return fmt.Sprintf("corpus_pool_%s.json", l) }

// ReadSentences は GCS の JSON 配列を読む。オブジェクトが無ければ nil, nil。
// プールを読み書きする dailyBatch 側（sentence_pool.go）も同じ入口を使う。
func ReadSentences(
	ctx context.Context, bucket *storage.BucketHandle, name string,
) ([]Sentence, error) {
	r, err := bucket.Object(name).NewReader(ctx)
	if err != nil {
		// Python は blob.exists() で分岐する。開けない理由は問わない。
		return nil, nil
	}
	data, err := io.ReadAll(r)
	r.Close()
	if err != nil {
		return nil, fmt.Errorf("%s の読み出しに失敗: %w", name, err)
	}
	var sentences []Sentence
	if err := json.Unmarshal(data, &sentences); err != nil {
		return nil, fmt.Errorf("%s の JSON 解析に失敗: %w", name, err)
	}
	if sentences == nil {
		sentences = []Sentence{}
	}
	return sentences, nil
}

func (b *CorpusBank) intn(n int) int {
	if b.Rand != nil {
		return b.Rand.Intn(n)
	}
	return rand.Intn(n)
}
