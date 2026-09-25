package sentence

import (
	"context"
	"log"
	"sync"

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
	) ([]TargetWord, error)
}

// CachedSentences は事前生成した例文の出どころ。
// 実装は FreeBank（free 例文バンク）と CorpusBank（premium の静的コーパス）。
//
// strictTopic はユーザーがテーマを指定したとき true。そのテーマの在庫が
// 無ければ別テーマの文で埋めずに nil を返してよい（LLM がそのテーマで作る）。
type CachedSentences interface {
	Pick(
		ctx context.Context, targetWord string, l lang.Lang, topic string, strictTopic bool,
	) (*Sentence, error)
}

// SentenceGenerator は LLM 生成。実装は Service。
type SentenceGenerator interface {
	GenerateSentence(
		ctx context.Context, params map[string]any, isPremium bool,
		targetWords []string, estimatedVocab int, l lang.Lang,
	) (*Sentence, error)
}

// CheckInput は判定1回ぶんの入力。UID・Topic・Tier・Stage は記録用。
type CheckInput struct {
	UID      string
	Sentence *Sentence
	KeyWord  string
	Topic    string
	Tier     string
	Lang     lang.Lang
	// Stage は "first"（生成直後）か "retry"（作り直し後）。
	Stage string
}

// CheckResult は判定1回ぶんの結果。Notes が空なら合格。
type CheckResult struct {
	// Notes は差し戻しプロンプトへ渡す指摘。
	Notes []string
	// Reason は閾値を超えた観点と確率（例: "共起 0.62"）。
	Reason string
	// Scores は全観点の確率。
	Scores map[string]float64
	Model  string
}

// Passed は合格かどうか。
func (r CheckResult) Passed() bool { return len(r.Notes) == 0 }

// Checker は LLM 生成直後の品質判定。実装は quality.Judge の包み（qualityChecker）。
type Checker interface {
	// Check は判定に失敗したら err を返す。呼び出し側は生成を止めない。
	Check(ctx context.Context, in CheckInput) (CheckResult, error)
}

// Quality は保存する文の最終的な判定結果（例文 doc の quality フィールド）。
// nil は「判定していない／判定に失敗した」で、プールには入れない。
type Quality struct {
	Passed bool
	// Retried は不合格で作り直した文かどうか。Passed はその作り直し後の判定。
	Retried bool
	Reason  string
	Scores  map[string]float64
	Model   string
}

func qualityFrom(r CheckResult, retried bool) *Quality {
	return &Quality{Passed: r.Passed(), Retried: retried, Reason: r.Reason, Scores: r.Scores, Model: r.Model}
}

// notesGenerator は差し戻しの指摘つきで作り直せる生成器。実装は Service。
type notesGenerator interface {
	GenerateSentenceWithNotes(
		ctx context.Context, params map[string]any, isPremium bool,
		targetWords []string, estimatedVocab int, l lang.Lang, notes []string,
	) (*Sentence, error)
}

// Producer は単語選定からキャッシュ／LLM 生成までをまとめた生成コア。
//
// 通常生成（generateThaiSentence）と毎日配信（deliverDailySentence）の共通経路。
type Producer struct {
	Selector WordSelector
	// Bank は free 例文バンク（GCS）。free のときだけ引く。
	Bank CachedSentences
	// Corpus は premium の静的コーパス（GCS）。premium のときだけ引く。
	// 当たらない語＝コーパスのランク上限より先へ進んだ人は LLM 生成へ落ちる。
	Corpus CachedSentences
	// History は既出例文の取得。nil なら既出を見ない（同じ文が再び出うる）。
	History History
	Service SentenceGenerator
	// Checker は LLM 生成直後の判定。nil、または ProduceRequest.QualityCheck が
	// 偽なら判定しない。バンク・コーパス由来の文は判定済みなので見ない。
	Checker Checker
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
	// QualityCheck が真なら LLM 生成した文を Checker にかけ、不合格なら指摘を
	// 付けて1回だけ作り直し、作り直した文をもう一度判定する（2026-09-25 の
	// 実測で作り直し後の合格 7/8）。作り直しても不合格なら作り直した文を使い、
	// Quality.Passed=false で保存する（プールに入らない）。元の文は不合格と
	// 分かっているので戻さない。
	QualityCheck bool
}

// Produced は Produce の結果。
type Produced struct {
	Sentence    *Sentence
	TargetWords []string
	// ChosenTopic は選定に使われた（あるいは自動選択された）テーマ。
	ChosenTopic string
	// FromCache は free 例文バンク由来かどうか。
	FromCache bool
	// Quality は判定結果。判定していなければ nil。
	Quality *Quality
}

// Produce は単語選定 → キャッシュ/LLM → generation_tier 付与までを行う
// （sentence_handlers.py:produce_sentence:181）。
//
// free はキャッシュ優先。CacheOnly ではキャッシュミス時に SelectRetry 回まで
// ターゲット語を引き直し、LLM は呼ばない。キャッシュに当たらなければ nil を返す。
func (p *Producer) Produce(
	ctx context.Context, db *firestore.Client, freqRank uvm.FreqRank, req ProduceRequest,
) (*Produced, error) {
	produced, err := p.ProduceBatch(ctx, db, freqRank, req, 1)
	if err != nil || len(produced) == 0 {
		return nil, err
	}
	return produced[0], nil
}

// ProduceBatch は n 本まとめて作る（毎日配信の5本セット）。
//
// 単語選定は1回にまとめる。GetSessionWords はプールから外しながら引くので、
// 1回の呼び出しで返る n 語は重複しない。呼び出しをまたぐ排他は無いため、
// 分けて引くと同じ key_word が同じセットに2本入りうる。
// そのあとの LLM 生成だけ語ごとに並列で回す（同時50本まで劣化しないことを
// 実測済み。設計 docs/design_daily_sentence_batch.md §3.1）。
//
// テーマは語ごと（TargetWord.Topic）。premium のおまかせだけセット内で散り、
// テーマ指定あり・free おまかせは全部同じテーマになる（SelectTargetWords 参照）。
//
// 戻り値は選定順。n 本に満たなくても揃ったぶんを返し、1本も作れなければ
// 空スライスを返す（CacheOnly の全ミス）。生成が全滅したときだけエラーを返す。
func (p *Producer) ProduceBatch(
	ctx context.Context, db *firestore.Client, freqRank uvm.FreqRank,
	req ProduceRequest, n int,
) ([]*Produced, error) {
	if n < 1 {
		n = 1
	}
	// UsePremiumPromptForVocab は今は req.UsePremiumSpec をそのまま返すので、
	// この呼び出しを外しても結果は変わらない（語彙による出し分けは廃止済み）。
	// Python 側も同じ形で呼び続けているので、対応を追えるよう残す。
	usePremiumPrompt := UsePremiumPromptForVocab(req.UsePremiumSpec, req.EstimatedVocab)

	var maxVocab *int
	if !usePremiumPrompt {
		v := uvm.FreeTierMaxVocab
		maxVocab = &v
	}

	// 事前生成した例文はティアで出どころが違う。free は従来どおり free
	// 例文バンク、premium は静的コーパス（設計 §3.4）。どちらも言語ごとの
	// ファイルで、まだ無ければ空で返るので下の LLM 生成へ落ちる。
	// CacheOnly（毎日配信の free 経路）でバンクが無ければ配信しない。
	bank := p.Bank
	if req.UsePremiumSpec {
		bank = p.Corpus
	}
	useBank := bank != nil
	// おまかせのテーマは語に近い上位5テーマからの抽選で、コーパスの
	// ラベルと一致しないことが多い（9/20〜 実測でヒット率が 75%→46%）。
	// テーマで在庫を諦めるのはユーザーが指定したときだけにする。
	strictTopic := strParam(req.Params, "topic") != ""

	// 既出の本文。バンクを引くときだけ要る（LLM 生成は毎回新しい文を作る）。
	// 読めなくてもバンクは引く。重複の可能性より、配信や生成が落ちるほうが重い。
	seen := map[string]bool{}
	if useBank && p.History != nil {
		if texts, err := p.History.SeenTexts(ctx, db, req.UID); err != nil {
			log.Printf("produce: 既出例文の取得に失敗 uid=%s: %v", req.UID, err)
		} else if texts != nil {
			// 以降このセットで出した文も足していくので、nil なら空の map のまま使う。
			seen = texts
		}
	}

	results := make([]*Produced, 0, n)
	// setTexts はこの呼び出しで出した本文。既出を無視して引き直すとき
	// （下の CacheOnly の最後の1周）でも、セット内の重複だけは避ける。
	setTexts := map[string]bool{}
	used := map[string]bool{}
	retries := max(1, req.SelectRetry)
	for range retries {
		want := n - len(results)
		if want <= 0 {
			break
		}
		selected, err := p.Selector.SelectTargetWords(
			ctx, db, freqRank, req.UID, req.Params,
			maxVocab, want, usePremiumPrompt, &req.EstimatedVocab, req.TestedVocab,
		)
		if err != nil {
			return nil, err
		}
		// 引き直し（CacheOnly）は前の周と別の呼び出しなので、そこだけ重複しうる。
		fresh := make([]TargetWord, 0, len(selected))
		for _, tw := range selected {
			if used[tw.Word] {
				continue
			}
			used[tw.Word] = true
			fresh = append(fresh, tw)
		}

		missed := fresh
		if useBank {
			missed = missed[:0:0]
			for _, tw := range fresh {
				cached, err := bank.Pick(ctx, tw.Word, req.Lang, tw.Topic, strictTopic)
				if err != nil {
					return nil, err
				}
				if cached == nil {
					missed = append(missed, tw)
					continue
				}
				if seen[cached.ThaiText] {
					// 既に出した文。バンクは語×テーマで1本しか持たないので、
					// 同じ key_word が再選出されるとそのまま同じ文が返る。
					// ここで在庫の別の文へ逃がさないのは、テーマ指定のときに
					// 頼まれたテーマから外れるため。指定どおりの新しい文を
					// 作れる LLM へ落とす（free は次の周で語を引き直す）。
					missed = append(missed, tw)
					continue
				}
				// 同じセットの中で二度出さない（語が違っても在庫が重なりうる）。
				seen[cached.ThaiText] = true
				setTexts[cached.ThaiText] = true
				cached.GenerationTier = GenerationTier(req.UsePremiumSpec)
				results = append(results, &Produced{
					Sentence:    cached,
					TargetWords: []string{tw.Word},
					ChosenTopic: tw.Topic,
					FromCache:   true,
				})
			}
		}
		if req.CacheOnly {
			// LLM は呼ばない。埋まらなかったぶんは次の周で語を引き直す。
			continue
		}

		generated, err := p.generate(ctx, req, missed)
		results = append(results, generated...)
		if len(results) == 0 && err != nil {
			return nil, err
		}
		break
	}

	// free の配信（CacheOnly）は LLM へ落とせないので、既出を避けきると
	// 1本も作れないことがある。free バンクは 112 語 × 4 本しかなく、
	// 続けている人はいずれ全部見る。配信を落とすより既出をもう一度出す
	// ほうがましなので、最後に既出を無視して引き直す。
	// premium は LLM 生成へ落ちるので、ここには来ない。
	if req.CacheOnly && useBank && len(results) == 0 && len(seen) > 0 {
		log.Printf("produce: 未出の在庫が尽きた uid=%s。既出を許して引き直す", req.UID)
		selected, err := p.Selector.SelectTargetWords(
			ctx, db, freqRank, req.UID, req.Params,
			maxVocab, n, usePremiumPrompt, &req.EstimatedVocab, req.TestedVocab,
		)
		if err != nil {
			return nil, err
		}
		for _, tw := range selected {
			cached, err := bank.Pick(ctx, tw.Word, req.Lang, tw.Topic, strictTopic)
			if err != nil {
				return nil, err
			}
			// この周だけ既出（seen）を見ない。セット内の重複だけ避ける。
			if cached == nil || setTexts[cached.ThaiText] {
				continue
			}
			setTexts[cached.ThaiText] = true
			cached.GenerationTier = GenerationTier(req.UsePremiumSpec)
			results = append(results, &Produced{
				Sentence:    cached,
				TargetWords: []string{tw.Word},
				ChosenTopic: tw.Topic,
				FromCache:   true,
			})
		}
	}
	return results, nil
}

// generate は語ごとに LLM 生成を並列で回す。戻り値は選定順。
//
// テーマは語ごと（TargetWord.Topic）。
// 一部が失敗しても成功したぶんを返す（配信は揃った本数で行う）。
// エラーは最初の1件だけ返し、呼び出し側は全滅のときだけエラーとして扱う。
func (p *Producer) generate(
	ctx context.Context, req ProduceRequest, picks []TargetWord,
) ([]*Produced, error) {
	if len(picks) == 0 {
		return nil, nil
	}
	produced := make([]*Produced, len(picks))
	errs := make([]error, len(picks))
	var wg sync.WaitGroup
	for i, pk := range picks {
		wg.Add(1)
		go func(i int, pk TargetWord) {
			defer wg.Done()
			callParams := map[string]any{}
			for k, v := range req.Params {
				callParams[k] = v
			}
			callParams["topic"] = pk.Topic

			s, err := p.Service.GenerateSentence(
				ctx, callParams, req.UsePremiumSpec, []string{pk.Word}, req.EstimatedVocab, req.Lang)
			if err != nil {
				errs[i] = err
				return
			}
			var q *Quality
			if req.QualityCheck {
				s, q = p.checkAndRetry(ctx, req, callParams, pk, s)
			}
			s.GenerationTier = GenerationTier(req.UsePremiumSpec)
			produced[i] = &Produced{
				Sentence:    s,
				TargetWords: []string{pk.Word},
				ChosenTopic: pk.Topic,
				Quality:     q,
			}
		}(i, pk)
	}
	wg.Wait()

	out := make([]*Produced, 0, len(picks))
	var firstErr error
	for i, pr := range produced {
		if pr != nil {
			out = append(out, pr)
			continue
		}
		if firstErr == nil {
			firstErr = errs[i]
		}
	}
	return out, firstErr
}

// checkAndRetry は s を判定し、不合格なら指摘つきで1回だけ作り直して判定し直す。
//
// 返す Quality が nil なのは、判定器が無い・判定に失敗したとき（プールに入れない）。
// 作り直しの生成に失敗したら元の文を不合格のまま返す。どの失敗でも生成・配信は止めない。
func (p *Producer) checkAndRetry(
	ctx context.Context, req ProduceRequest, params map[string]any, pk TargetWord, s *Sentence,
) (*Sentence, *Quality) {
	rg, ok := p.Service.(notesGenerator)
	if p.Checker == nil || !ok {
		return s, nil
	}
	in := CheckInput{
		UID: req.UID, Sentence: s, KeyWord: pk.Word, Topic: pk.Topic,
		Tier: GenerationTier(req.UsePremiumSpec), Lang: req.Lang, Stage: "first",
	}
	first, err := p.Checker.Check(ctx, in)
	if err != nil {
		log.Printf("produce: quality check failed key_word=%s: %v", pk.Word, err)
		return s, nil
	}
	if first.Passed() {
		return s, qualityFrom(first, false)
	}
	retried, err := rg.GenerateSentenceWithNotes(
		ctx, params, req.UsePremiumSpec, []string{pk.Word}, req.EstimatedVocab, req.Lang, first.Notes)
	if err != nil {
		log.Printf("produce: quality retry failed key_word=%s: %v", pk.Word, err)
		return s, qualityFrom(first, false)
	}
	in.Sentence, in.Stage = retried, "retry"
	second, err := p.Checker.Check(ctx, in)
	if err != nil {
		log.Printf("produce: quality recheck failed key_word=%s: %v", pk.Word, err)
		return retried, nil
	}
	return retried, qualityFrom(second, true)
}
