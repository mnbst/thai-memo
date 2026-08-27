package sentence

import (
	"fmt"
	"math"
	"strings"

	"github.com/mnbst/thai-memo/functions/go/internal/lang"
	"github.com/mnbst/thai-memo/functions/go/internal/wordclass"
)

// functions/python/prompts.py の移植（ロジック部分）。
// 文字列データは prompts_data.go に自動生成してある。

// SystemPrompt は tier・語彙スコア・訳文言語に応じた固定システムプロンプトを返す。
//
// ja は毎回同じ文字列（生成済み定数）を返す。
// プロンプトキャッシュの prefix を壊さないため、組み立て直さないこと。
func SystemPrompt(isPremium bool, l lang.Lang) string {
	tier := "free"
	if isPremium {
		tier = "premium"
	}
	byLang := systemPrompts[tier]
	if s, ok := byLang[string(l)]; ok {
		return s
	}
	return byLang[string(lang.Default)]
}

// UsePremiumPromptForVocab は premium ユーザーなら常に premium プロンプトを使う。
//
// 語彙スコアによる出し分けは廃止済みで、引数は互換のために残っている。
func UsePremiumPromptForVocab(isPremium bool, estimatedVocab int) bool {
	return isPremium
}

// GateTopicsForVocab は estimated_vocab に応じて自動選択用テーマ候補を絞る。
// 全て落ちた場合は元のプールをそのまま返す。
func GateTopicsForVocab(pool []string, estimatedVocab int) []string {
	filtered := make([]string, 0, len(pool))
	for _, item := range pool {
		if estimatedVocab >= topicMinVocab[item] {
			filtered = append(filtered, item)
		}
	}
	if len(filtered) == 0 {
		return pool
	}
	return filtered
}

// computeLengthHint は estimated_vocab から文の長さヒントを返す。
//
//	100未満   : introLengthHints の段階指定
//	100-1499  : 7単語から16単語へ線形補間
//	1500以上  : 自然な長さ
func computeLengthHint(estimatedVocab int) string {
	if estimatedVocab >= 1500 {
		return "自然な長さ"
	}
	if estimatedVocab < 100 {
		for _, h := range introLengthHints {
			if estimatedVocab >= h.MinVocab {
				return h.Hint
			}
		}
	}
	words := max(minLengthHintWords,
		pyRound(7+float64(estimatedVocab-100)/1400*9))
	return fmt.Sprintf("〜%d単語", words)
}

// pyRound は Python の round()（銀行家丸め＝偶数丸め）。
// Go の math.Round は 0 から遠い方へ丸めるので一致しない。
func pyRound(v float64) int {
	r := math.RoundToEven(v)
	return int(r)
}

// Difficulty は estimated_vocab から決まる難易度指定。
type Difficulty struct {
	Label     string
	VocabHint string
	Length    string
}

// GetDifficulty は estimated_vocab から難易度レベルを返す。
func GetDifficulty(estimatedVocab int) Difficulty {
	level := difficultyLevels[len(difficultyLevels)-1]
	for _, lv := range difficultyLevels {
		if estimatedVocab <= lv.MaxVocab {
			level = lv
			break
		}
	}
	return Difficulty{
		Label:     level.Label,
		VocabHint: level.VocabHint,
		Length:    computeLengthHint(estimatedVocab),
	}
}

// dropRulesBanningTargets はターゲット語を禁止しているルールを落とす。
func dropRulesBanningTargets(rules, targetWords []string) []string {
	if len(targetWords) == 0 {
		return rules
	}
	var markers []string
	for _, word := range targetWords {
		if marker, ok := ruleBannedWords[word]; ok {
			markers = append(markers, marker)
		}
	}
	if len(markers) == 0 {
		return rules
	}

	out := make([]string, 0, len(rules))
	for _, r := range rules {
		banned := false
		for _, m := range markers {
			if strings.Contains(r, m) {
				banned = true
				break
			}
		}
		if !banned {
			out = append(out, r)
		}
	}
	return out
}

// numberedRules は "1. …" の形に番号を振って連結する。
func numberedRules(rules []string) string {
	lines := make([]string, 0, len(rules))
	for i, r := range rules {
		lines = append(lines, fmt.Sprintf("%d. %s", i+1, r))
	}
	return strings.Join(lines, "\n")
}

func stepsFor(l lang.Lang) string {
	if s, ok := translationSteps[string(l)]; ok {
		return s
	}
	return translationSteps[string(lang.JA)]
}

// BuildRegisterConstraint はテーマで出し分けた【最後に確認】ブロックを返す。
//
// 残る条件分岐はテーマ由来の1つと、ターゲット語がルールの禁止語と衝突する場合の
// 除去（ruleBannedWords）だけ。
func BuildRegisterConstraint(topic string, targetWords []string, l lang.Lang) string {
	rules := append([]string(nil), spokenRegisterRules...)
	rules = append(rules, translationRegisterRules[string(l)]...)
	rules = append(rules, alwaysRules...)

	// 恋愛 / タイBLドラマ
	if topic == Topics[14] || topic == Topics[15] {
		rules = append(rules, romanceTopicRules...)
	}
	rules = dropRulesBanningTargets(rules, targetWords)

	return "【最後に確認】\n" + numberedRules(rules) + "\n\n" + stepsFor(l)
}

// BuildFreeConstraint は free 用の【最後に確認】ブロックを返す。
//
// free は BuildRegisterConstraint を通らないため、末尾配置で効くと実証済みの
// 訳文の手順が丸ごと欠けていた（2026-08-21 に追加）。
func BuildFreeConstraint(targetWords []string, l lang.Lang) string {
	rules := dropRulesBanningTargets(
		append([]string(nil), freeAlwaysRules...), targetWords)
	steps := stepsFor(l)
	if len(rules) == 0 {
		return steps
	}
	return "【最後に確認】\n" + numberedRules(rules) + "\n\n" + steps
}

// BuildRelationConstraint は話し手と聞き手の関係ブロックを返す。
// relation が空なら空文字。
func BuildRelationConstraint(relation string) string {
	if relation == "" {
		return ""
	}
	status, intimacy, _ := strings.Cut(relation, "／")
	return strings.NewReplacer(
		"{status}", status, "{intimacy}", intimacy,
	).Replace(relationBlock)
}

// BuildWordClassConstraint はターゲット語のクラスに応じた末尾ブロックを組み立てる。
// 未分類（内容語）だけなら空文字を返し、ブロック自体を付けない。
func BuildWordClassConstraint(targetWords []string) string {
	classIDs := wordclass.ClassifyAll(targetWords)
	if len(classIDs) == 0 {
		return ""
	}

	classes := make([]wordclass.Class, 0, len(classIDs))
	labels := make([]string, 0, len(classIDs))
	for _, cid := range classIDs {
		c, ok := wordclass.Get(cid)
		if !ok {
			continue
		}
		classes = append(classes, c)
		labels = append(labels, c.Label)
	}

	lines := []string{fmt.Sprintf("【ターゲット語は%s】", strings.Join(labels, "・"))}
	for _, c := range classes {
		if c.FunctionWord {
			lines = append(lines, functionWordSteps)
			break
		}
	}
	for _, c := range classes {
		if c.Rule != "" {
			lines = append(lines, c.Rule)
		}
	}
	return strings.Join(lines, "\n")
}
