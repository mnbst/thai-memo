package sentence

import (
	"fmt"
	"strings"

	"github.com/mnbst/thai-memo/functions/go/internal/lang"
)

// ResolvedParams は抽選で確定した生成パラメータ。
//
// 抽選（時制・関係・サブテーマ）は ResolveGenerationParams が行い、
// 組み立て（BuildPrompt）は確定値だけを受け取る。こう分けておくと
// 組み立て側が決定的になり、プロンプト全文を差分テストで固定できる。
type ResolvedParams struct {
	Topic string
	// TopicOptions は Topic が空のとき LLM に提示する候補。
	TopicOptions []string
	SubTheme     string
	TimeFrame    string
	Relation     string
}

// DramaSection は BL ドラマ回の専用ブロック。
// ドラマ回でなければゼロ値。
type DramaSection struct {
	Context  string
	Required string
}

// BuildPrompt はプロンプトを構築する（free/premium 共通）。
//
// 戻り値は プロンプト文字列 と、生成後に context へ注入する確定値。
// 文体・感情はサーバーで決めないので入らず、LLM が生成して返す。
func BuildPrompt(
	resolved ResolvedParams,
	targetWords []string,
	estimatedVocab int,
	isPremium bool,
	l lang.Lang,
	drama DramaSection,
) (string, map[string]any) {
	diff := GetDifficulty(estimatedVocab)
	promptIsPremium := UsePremiumPromptForVocab(isPremium, estimatedVocab)

	topic := resolved.Topic
	subTheme := resolved.SubTheme
	timeFrame := resolved.TimeFrame
	relation := resolved.Relation

	// 「さっき起きた出来事」だけ、相手の行動を求める文（依頼・指示・禁止）と
	// 両立しない。【可能な限り反映】の逃げ道は「上位の指示と衝突する場合」に
	// 限られ、文型の選択は LLM の自由なのでこの衝突を拾えない。
	// 条件が確定している時点にだけ但し書きを付ける。
	timeFrameNote := ""
	if timeFrame == TimeFrames[1] {
		timeFrameNote = "（すでに起きた出来事を述べる文に付ける。" +
			"相手のこれからの行動を求める文にするなら、この時点は落とす）"
	}
	timeFrameLine := ""
	if timeFrame != "" {
		timeFrameLine = fmt.Sprintf("- 話している時点: %s%s\n", timeFrame, timeFrameNote)
	}
	subThemeLine := ""
	if subTheme != "" {
		subThemeLine = fmt.Sprintf("- サブテーマ: %s\n", subTheme)
	}

	isDrama := topic == Topics[15]
	var topicLine string
	switch {
	case isDrama:
		// ドラマ回は場面をドラマ側のブロックが決めるため付けない。
		topicLine = ""
		subThemeLine = ""
		timeFrameLine = ""
		timeFrame = ""
		relation = ""
	case topic != "":
		topicLine = fmt.Sprintf("- テーマ: %s\n", topic)
	default:
		// テーマ未確定。候補を列挙してターゲット単語に合うものを選ばせる。
		// 選択肢を閉じることで estimated_vocab のレベル別ゲートは維持される。
		// BLドラマだけは除く。専用ブロックがサーバー側の topic 確定を
		// 前提にしており、LLM が選んでも発火しない。
		var opts []string
		for _, t := range resolved.TopicOptions {
			if t != Topics[15] {
				opts = append(opts, t)
			}
		}
		topicLine = "- テーマ: 次から1つ選ぶ（ターゲット単語が最も自然に収まるもの）\n" +
			"  " + strings.Join(opts, "／") + "\n"
	}

	// プロンプトで指定した値のみ確定値として記録する。
	// 欠けたキーは呼び出し側が LLM に生成させる（BuildResponseSchema）。
	context := map[string]any{}
	if topic != "" {
		context["topic"] = topic
	}
	if !isDrama {
		// 偏りを後から集計できるように、サーバーが決めた値は全て残す。
		if subTheme != "" {
			context["subTheme"] = subTheme
		}
		if timeFrame != "" {
			context["timeFrame"] = timeFrame
		}
		if relation != "" {
			context["relation"] = relation
		}
	}

	// ブロックは "\n\n" で連結する。drama 未適用時に空行だけが残らないよう、
	// 空のブロックは積まない。
	var sections []string
	if len(targetWords) > 0 {
		sections = append(sections,
			"【最優先】以下のタイ語単語を必ず含めてください:\n"+
				"<target_words>\n"+strings.Join(targetWords, ", ")+"\n</target_words>")
	}
	if drama.Context != "" {
		sections = append(sections, strings.TrimSpace(drama.Context))
	}
	// 「- 長さ」は難易度制御の実体。外すと帯の差が消える。消さないこと。
	sections = append(sections, fmt.Sprintf(
		"【必須】難易度:\n- 語彙レベル: %s（%s）\n- 長さ: %s",
		diff.Label, diff.VocabHint, diff.Length))
	if drama.Required != "" {
		sections = append(sections, strings.TrimSpace(drama.Required))
	}

	elements := topicLine + subThemeLine + timeFrameLine
	if strings.TrimSpace(elements) != "" {
		sections = append(sections,
			"【可能な限り反映】以下の要素を、自然なタイ語になる範囲で取り入れてください。"+
				"上位の指示と衝突する場合は、この要素を落としてください。\n"+
				strings.TrimRight(elements, " \t\n\v\f\r"))
	}

	// 語彙レジスタ制約は末尾に置く（system prompt では守られなかったため）。
	if promptIsPremium {
		sections = append(sections, BuildRegisterConstraint(topic, targetWords, l))
	} else {
		sections = append(sections, BuildFreeConstraint(targetWords, l))
	}

	// 話し手と聞き手の関係は premium のみ（free は入門帯で文が短く、
	// 人称・文末詞を足す余地が無い）。
	if promptIsPremium {
		if block := BuildRelationConstraint(relation); block != "" {
			sections = append(sections, block)
		}
	}

	// 語クラス別の指示は最末尾（該当するクラスが無ければ付かない）。
	if block := BuildWordClassConstraint(targetWords); block != "" {
		sections = append(sections, block)
	}

	return strings.Join(sections, "\n\n"), context
}
