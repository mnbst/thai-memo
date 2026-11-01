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
// バンクは言語ごとの JSON として GCS に配置する。
// まだ無い言語（アップロード前・新言語の追加直後）は空で、呼び出し側が
// LLM 生成へ落ちる。
//
// これに加えて、free で LLM 生成された例文のうち judge を通ったものを貯めた
// プール（free_pool_<lang>.json、dailyBatch が毎日書き出す）も重ねる。
// premium のプール（CorpusBank）とはファイルを分け、ティアごとに洗い直せるようにする。
type FreeBank struct {
	// ProjectID は GCS バケット名 {ProjectID}-uvm-data に使う。
	ProjectID string
	// Rand は抽選に使う。nil なら共有の乱数源。テストで固定する。
	Rand *rand.Rand

	mu    sync.Mutex
	cache map[lang.Lang][]Sentence
}

// Sentences は GCS から free_sentences_<lang>.json とプール（free_pool_<lang>.json）を
// 読み込みキャッシュする（sentence_service.py:get_free_sentences:224）。
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

	// プールは運用が始まるまで存在しない。無ければ無いまま進む。
	pool, err := ReadSentences(ctx, bucket, FreePoolObject(l))
	if err != nil {
		return nil, err
	}
	if pool != nil {
		sentences = append(sentences, pool...)
		log.Printf("free bank pool loaded: lang=%s sentences=%d", l, len(pool))
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
// strictTopic は見ない（free は指定テーマでも在庫を優先する）。
//
// ただしバンクに1本も無いテーマ（交通など）は nil を返し、その場で生成させる。
// 別テーマの在庫で埋めると、そのテーマが free に一度も出なくなる。
func (b *FreeBank) Pick(
	ctx context.Context, targetWord string, l lang.Lang, topic string, _ bool,
) (*Sentence, error) {
	sentences, err := b.Sentences(ctx, l)
	if err != nil {
		return nil, err
	}
	var candidates []Sentence
	topicStocked := topic == ""
	for _, s := range sentences {
		if s.KeyWord == targetWord {
			candidates = append(candidates, s)
		}
		if t, _ := s.Context["topic"].(string); t == topic {
			topicStocked = true
		}
	}
	if !topicStocked {
		return nil, nil
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

	picked := candidates[b.intn(len(candidates))]
	localizeBanked(&picked, l)
	return &picked, nil
}

// PickUnseen は target_word に紐づく free 例文を、バンクの並び順で未出（seen に無い）の
// ものから1件返す。preferred（ヒアリングの用途から広げたテーマ、日本語ラベル）に
// 当たる文を先に出し、当たる文が残っていなければ別テーマの未出で埋める。
// 全部既出か、語の例文が無ければ nil（呼び出し側が LLM で作る）。
//
// Pick は候補から一様に引くので、未出の文が残っていても既出の文を引けば LLM へ
// 落ちていた。free のテーマはおまかせの一様抽選なので、在庫の無いテーマを
// 引いたときも同じく LLM へ落ちていた。語の選定はそのままに、語に紐づく文を
// 順に出し切ってから LLM を呼ぶ。
func (b *FreeBank) PickUnseen(
	ctx context.Context, targetWord string, l lang.Lang, seen map[string]bool,
	preferred map[string]bool,
) (*Sentence, string, error) {
	sentences, err := b.Sentences(ctx, l)
	if err != nil {
		return nil, "", err
	}
	// en / ko のバンクはテーマを訳したラベルで持つので、訳した側でも当てる。
	want := map[string]bool{}
	labels, localized := contextLabelsByLang[l]
	for t := range preferred {
		want[t] = true
		if localized {
			want[labels.topic(t)] = true
		}
	}
	var fallback *Sentence
	for i := range sentences {
		s := sentences[i]
		if s.KeyWord != targetWord || seen[s.ThaiText] {
			continue
		}
		topic, _ := s.Context["topic"].(string)
		if len(want) > 0 && !want[topic] {
			if fallback == nil {
				fallback = &sentences[i]
			}
			continue
		}
		localizeBanked(&s, l)
		return &s, topic, nil
	}
	if fallback == nil {
		return nil, "", nil
	}
	s := *fallback
	topic, _ := s.Context["topic"].(string)
	localizeBanked(&s, l)
	return &s, topic, nil
}

func (b *FreeBank) intn(n int) int {
	if b.Rand != nil {
		return b.Rand.Intn(n)
	}
	return rand.Intn(n)
}
