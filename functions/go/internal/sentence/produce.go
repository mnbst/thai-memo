package sentence

import (
	"context"

	"cloud.google.com/go/firestore"

	"github.com/mnbst/thai-memo/functions/go/internal/lang"
	"github.com/mnbst/thai-memo/functions/go/internal/uvm"
)

// GenerationTier は保存・レスポンスに載せるティア表記。
func GenerationTier(usePremiumSpec bool) string {
	if usePremiumSpec {
		return "premium"
	}
	return "free"
}

// WordSelector はターゲット語を選ぶ。実装は TargetWordSelector。
type WordSelector interface {
	SelectTargetWords(
		ctx context.Context, db *firestore.Client, freqRank uvm.FreqRank,
		uid string, params map[string]any,
		maxVocab *int, count int, isPremium bool, estimatedVocab *int,
		testedVocab int,
	) ([]string, string, error)
}

// CachedSentences は free 例文バンク。実装は FreeBank。
type CachedSentences interface {
	Pick(ctx context.Context, targetWord string, l lang.Lang, topic string) (*Sentence, error)
}

// SentenceGenerator は LLM 生成。実装は Service。
type SentenceGenerator interface {
	GenerateSentence(
		ctx context.Context, params map[string]any, isPremium bool,
		targetWords []string, estimatedVocab int, l lang.Lang,
	) (*Sentence, error)
}

// Producer は単語選定からキャッシュ／LLM 生成までをまとめた生成コア。
//
// 通常生成（generateThaiSentence）と毎日配信（deliverDailySentence）の共通経路。
type Producer struct {
	Selector WordSelector
	Bank     CachedSentences
	Service  SentenceGenerator
}

// ProduceRequest は Produce の条件。
type ProduceRequest struct {
	UID    string
	Params map[string]any
	// UsePremiumSpec が真なら premium 相当の生成（テーマ採用・語彙上限なし）。
	UsePremiumSpec bool
	EstimatedVocab int
	// TestedVocab は語彙テストの測定値（原点）。key_word 帯の下端はここより
	// 下へ行かない。未受験は 0。
	TestedVocab int
	// CacheOnly が真なら LLM を呼ばない（配信の free 経路）。
	CacheOnly bool
	// SelectRetry は CacheOnly でキャッシュミスしたときの引き直し回数。
	SelectRetry int
	Lang        lang.Lang
}

// Produced は Produce の結果。
type Produced struct {
	Sentence    *Sentence
	TargetWords []string
	// ChosenTopic は選定に使われた（あるいは自動選択された）テーマ。
	ChosenTopic string
	// FromCache は free 例文バンク由来かどうか。
	FromCache bool
}

// Produce は単語選定 → キャッシュ/LLM → generation_tier 付与までを行う
// （sentence_handlers.py:produce_sentence:181）。
//
// free はキャッシュ優先。CacheOnly ではキャッシュミス時に SelectRetry 回まで
// ターゲット語を引き直し、LLM は呼ばない。キャッシュに当たらなければ nil を返す。
func (p *Producer) Produce(
	ctx context.Context, db *firestore.Client, freqRank uvm.FreqRank, req ProduceRequest,
) (*Produced, error) {
	// UsePremiumPromptForVocab は今は req.UsePremiumSpec をそのまま返すので、
	// この呼び出しを外しても結果は変わらない（語彙による出し分けは廃止済み）。
	// Python 側も同じ形で呼び続けているので、対応を追えるよう残す。
	usePremiumPrompt := UsePremiumPromptForVocab(req.UsePremiumSpec, req.EstimatedVocab)

	var maxVocab *int
	if !usePremiumPrompt {
		v := uvm.FreeTierMaxVocab
		maxVocab = &v
	}

	var targetWords []string
	chosenTopic := ""
	retries := max(1, req.SelectRetry)
	for range retries {
		var err error
		targetWords, chosenTopic, err = p.Selector.SelectTargetWords(
			ctx, db, freqRank, req.UID, req.Params,
			maxVocab, 1, usePremiumPrompt, &req.EstimatedVocab, req.TestedVocab,
		)
		if err != nil {
			return nil, err
		}

		// free 例文バンク（GCS）は言語ごとに事前生成したもの（設計 §3.4）。
		// その言語のバンクがまだ無ければ空で返るので、下の LLM 生成へ落ちる。
		// CacheOnly（毎日配信の free 経路）でバンクが無ければ配信しない。
		if !req.UsePremiumSpec && p.Bank != nil {
			cached, err := p.Bank.Pick(ctx, targetWords[0], req.Lang, chosenTopic)
			if err != nil {
				return nil, err
			}
			if cached != nil {
				cached.GenerationTier = GenerationTier(req.UsePremiumSpec)
				return &Produced{
					Sentence:    cached,
					TargetWords: targetWords,
					ChosenTopic: chosenTopic,
					FromCache:   true,
				}, nil
			}
		}
		if !req.CacheOnly {
			break
		}
	}

	if req.CacheOnly {
		return nil, nil
	}

	params := map[string]any{}
	for k, v := range req.Params {
		params[k] = v
	}
	params["topic"] = chosenTopic

	s, err := p.Service.GenerateSentence(
		ctx, params, req.UsePremiumSpec, targetWords, req.EstimatedVocab, req.Lang)
	if err != nil {
		return nil, err
	}
	s.GenerationTier = GenerationTier(req.UsePremiumSpec)
	return &Produced{
		Sentence:    s,
		TargetWords: targetWords,
		ChosenTopic: chosenTopic,
	}, nil
}
