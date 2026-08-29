package sentence

import (
	"context"
	"fmt"
	"log"
	"strings"

	"github.com/mnbst/thai-memo/functions/go/internal/lang"
	"github.com/mnbst/thai-memo/functions/go/internal/thainlp"
	"github.com/mnbst/thai-memo/functions/go/internal/wordgap"
)

// Generator は LLM を呼んで例文を組み立てる。
type Generator interface {
	// GenerateSentence は system/user プロンプトから構造化レスポンスを得る。
	GenerateSentence(ctx context.Context, systemPrompt, userPrompt string,
		isPremium bool, tierLabel string, schema map[string]any) (map[string]any, error)
}

// ApplyResponseCompat は LLM の省トークン形式を、保存・クライアント互換の形に戻す。
//
//   - target_notes を word_breakdown[].notes に展開する（非対象は空文字）
//   - context.topic / style / emotion にサーバー確定値を注入する
//
// sentence_service.py:_apply_response_compat:404 の移植。
func ApplyResponseCompat(s *Sentence, resolvedContext map[string]any) {
	// 同じ語が複数回 target_notes に出た場合は後勝ち（Python の dict 内包表記）。
	notesByWord := make(map[string]string, len(s.TargetNotes))
	order := make([]string, 0, len(s.TargetNotes))
	for _, item := range s.TargetNotes {
		word := strings.TrimSpace(item.Word)
		if _, seen := notesByWord[word]; !seen {
			order = append(order, word)
		}
		notesByWord[word] = item.Note
	}
	s.TargetNotes = nil

	for i := range s.WordBreakdown {
		word := strings.TrimSpace(s.WordBreakdown[i].Word)
		note := notesByWord[word]
		if note == "" {
			// 完全一致しない場合だけ ๆ の表記ゆれを吸収して探す。
			// 先に見つかったものを採るので、走査順を保つ必要がある。
			for _, key := range order {
				if MatchWord(word, key) {
					note = notesByWord[key]
					break
				}
			}
		}
		s.WordBreakdown[i].Notes = note
	}

	if len(resolvedContext) > 0 {
		merged := make(map[string]any, len(s.Context)+len(resolvedContext))
		for k, v := range s.Context {
			merged[k] = v
		}
		for k, v := range resolvedContext {
			merged[k] = v
		}
		s.Context = merged
	}
}

// EnrichWithNLP は音節分割・発音・品詞を word_breakdown に足し、
// 文全体の発音を組み立てる。
func EnrichWithNLP(s *Sentence, l lang.Lang) {
	enriched, pronunciation, converted := thainlp.Enrich(s.BreakdownWords(), l)
	for i := range s.WordBreakdown {
		s.WordBreakdown[i].Syllables = enriched[i].Syllables
		s.WordBreakdown[i].Pronunciation = enriched[i].Pronunciation
		s.WordBreakdown[i].GrammaticalRole = enriched[i].GrammaticalRole
	}
	// 1語も変換できなかったときだけ既存の発音を残す。
	if converted {
		s.Pronunciation = pronunciation
	}
}

// RepairWordBreakdown は word_breakdown の欠落を、欠落分だけの補完クエリ
// 1 回で埋める。
//
// 文全体は作り直さない（コスト・レイテンシが見合わないため）。補完できなかった
// 場合は文全体の発音だけ thai_text から作り直し、発音が欠けたままにしない。
// sentence_service.py:_repair_word_breakdown:520 の移植。
func RepairWordBreakdown(ctx context.Context, gen Generator, s *Sentence, req *Request) {
	gaps := wordgap.FindGaps(s.ThaiText, s.gapWords())
	if len(gaps) == 0 {
		return
	}

	segments := make([]string, 0, len(gaps))
	for _, g := range gaps {
		segments = append(segments, g.Segment)
	}
	log.Printf("word_breakdown gap detected: %v in %s", segments, s.ThaiText)

	if repairable(gaps) {
		if filled, err := fillGaps(ctx, gen, s, gaps, req); err != nil {
			// 補完の失敗で生成全体を落とさない。
			log.Printf("word_breakdown gap fill failed: %v", err)
		} else if merged, ok := wordgap.ApplyGapWords(
			s.ThaiText, s.gapWords(), gaps, filled); ok {
			applyMerged(s, merged)
			req.enrich(s)
			return
		}
	}

	// RepairPronunciation は「thai_text が空」「変換に失敗」のどちらでも "" を返し、
	// Python 側もその2つでは pronunciation を書き換えない。空を弾いても弾かなくても
	// 差が出るのは「非空の thai_text が空の発音に変換される」場合だけで、これは起きない。
	if pron := wordgap.RepairPronunciation(s.ThaiText); pron != "" {
		s.Pronunciation = pron
	}
}

// repairable は全ての欠落が補完可能か（綴り不一致が混じっていないか）。
func repairable(gaps []wordgap.Gap) bool {
	for _, g := range gaps {
		if g.Index < 0 {
			return false
		}
	}
	return true
}

func fillGaps(
	ctx context.Context, gen Generator, s *Sentence, gaps []wordgap.Gap, req *Request,
) ([]wordgap.Word, error) {
	raw, err := gen.GenerateSentence(ctx,
		wordgap.GapSystemPrompt,
		wordgap.BuildGapPrompt(s.ThaiText, gaps),
		req.IsPremium,
		req.TierLabel+"-gap",
		wordgap.GapResponseSchema())
	if err != nil {
		return nil, err
	}

	var filled struct {
		Words []wordgap.Word `json:"words"`
	}
	if err := remarshal(raw, &filled); err != nil {
		return nil, err
	}
	return filled.Words, nil
}

// applyMerged は補完後の語列を word_breakdown へ戻す。
//
// ApplyGapWords は既存の語を並び順そのままに残して欠落分を挿し込むだけなので、
// 前から突き合わせれば既存の語を特定できる。既存の語は notes を持っている
// （target_notes から展開済み）ので、作り直さずそのまま引き継ぐ。
// NLP の情報はこの直後に付け直すため引き継がなくてよい。
func applyMerged(s *Sentence, merged []wordgap.Word) {
	out := make([]Word, len(merged))
	next := 0
	for i, m := range merged {
		if next < len(s.WordBreakdown) &&
			s.WordBreakdown[next].Word == m.Word &&
			s.WordBreakdown[next].Meaning == m.Meaning {
			out[i] = s.WordBreakdown[next]
			next++
			continue
		}
		out[i] = Word{Word: m.Word, Meaning: m.Meaning}
	}
	s.WordBreakdown = out
}

// Request は 1 文ぶんの生成条件。
type Request struct {
	SystemPrompt string
	Prompt       string
	IsPremium    bool
	TierLabel    string
	// TargetWords は文中に独立した語として出すべき単語。空なら検証しない。
	TargetWords []string
	// ResolvedContext はサーバー側で確定済みのテーマ・文体など。
	// ここに入っているフィールドは LLM に生成させない。
	ResolvedContext map[string]any
	Lang            lang.Lang

	// Enrich は NLP 後処理の差し替え用。nil なら EnrichWithNLP。
	Enrich func(*Sentence, lang.Lang)
}

func (r *Request) enrich(s *Sentence) {
	if r.Enrich != nil {
		r.Enrich(s, r.Lang)
		return
	}
	EnrichWithNLP(s, r.Lang)
}

// GenerateSingle は LLM で 1 文を生成し NLP 後処理を適用する。
//
// ターゲット語が欠けていれば指摘して 1 回だけ作り直す。綴り不一致
// （word_breakdown に thai_text へ無い語がある）も欠落補完では直せないので
// 同じ枠で作り直す。どちらも直らなければエラー。
// sentence_service.py:_generate_single:561 の移植。
func GenerateSingle(ctx context.Context, gen Generator, req Request) (*Sentence, error) {
	currentPrompt := req.Prompt
	var missing []string

	for attempt := 0; attempt <= MaxRetry; attempt++ {
		raw, err := gen.GenerateSentence(ctx, req.SystemPrompt, currentPrompt,
			req.IsPremium, req.TierLabel, SchemaFor(req.ResolvedContext, req.Lang))
		if err != nil {
			return nil, err
		}
		s, err := FromMap(raw)
		if err != nil {
			return nil, fmt.Errorf("LLM_API_ERROR: unexpected structured output: %w", err)
		}

		ApplyResponseCompat(s, req.ResolvedContext)
		// 軸ラベル（テーマ・文体など）はサーバー側の日本語定数なので、en は英語へ。
		s.Context = LocalizeContext(s.Context, req.Lang)

		compacted := CompactYamok(s.ThaiText)
		text, words := NormalizeThaiSpacing(s.ThaiText, s.BreakdownWords())
		if text != compacted {
			log.Printf("thai_text word-split collapsed: %s -> %s", compacted, text)
		}
		s.ThaiText = text
		for i := range s.WordBreakdown {
			s.WordBreakdown[i].Word = words[i]
		}
		req.enrich(s)

		missing = ValidateTargetWords(s.BreakdownWords(), req.TargetWords)
		if len(missing) > 0 {
			log.Printf("Target word validation failed (attempt %d): missing=%v",
				attempt+1, missing)
			currentPrompt = BuildRetryPrompt(req.Prompt, missing)
			continue
		}

		// 綴り不一致は欠落補完では直せないため、1 回だけ作り直す。
		if attempt < MaxRetry && HasUnrepairableBreakdown(s.ThaiText, s.gapWords()) {
			log.Printf("thai_text/word_breakdown mismatch (attempt %d): %s",
				attempt+1, s.ThaiText)
			currentPrompt = BuildMismatchRetryPrompt(req.Prompt, s.ThaiText)
			continue
		}

		RepairWordBreakdown(ctx, gen, s, &req)
		return s, nil
	}

	return nil, fmt.Errorf("LLM_API_ERROR: target words missing after retries: %s",
		strings.Join(missing, ", "))
}

// DramaBuilder は BL ドラマ回の専用ブロックを組み立てる。
// 実装は themes/bl_drama.py の移植。nil ならドラマ回でもブロックを付けない。
type DramaBuilder interface {
	BuildDramaSection(targetWords []string) DramaSection
}

// Service は例文生成の入口。
type Service struct {
	Gen      Generator
	Resolver *Resolver
	Drama    DramaBuilder
}

// GenerateSentence は LLM で例文を生成し、NLP 後処理を適用する。
// sentence_service.py:generate_sentence:667 の移植。
func (s *Service) GenerateSentence(
	ctx context.Context, params map[string]any, isPremium bool,
	targetWords []string, estimatedVocab int, l lang.Lang,
) (*Sentence, error) {
	tierLabel := "free"
	if isPremium {
		tierLabel = "premium"
	}

	resolved := s.Resolver.Resolve(ctx, params, targetWords, estimatedVocab)

	// ドラマ回は場面をドラマ側のブロックが決めるので、テーマ・サブテーマ・
	// 時点・関係の行を出さない（BuildPrompt 側で落とす）。
	var drama DramaSection
	if s.Drama != nil && resolved.Topic == Topics[15] {
		drama = s.Drama.BuildDramaSection(targetWords)
	}

	prompt, resolvedContext := BuildPrompt(
		resolved, targetWords, estimatedVocab, isPremium, l, drama)

	return GenerateSingle(ctx, s.Gen, Request{
		SystemPrompt:    SystemPrompt(isPremium, l),
		Prompt:          prompt,
		IsPremium:       isPremium,
		TierLabel:       tierLabel,
		TargetWords:     targetWords,
		ResolvedContext: resolvedContext,
		Lang:            l,
	})
}
