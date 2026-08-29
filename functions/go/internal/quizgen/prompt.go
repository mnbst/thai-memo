package quizgen

import (
	"fmt"
	"strings"

	"github.com/mnbst/thai-memo/functions/go/internal/lang"
)

// プロンプトは JS 版（quizGenerationService.ts）と1バイトも変えないこと。
// 生成物の質が直接変わるうえ、dummy_reasons の書式は
// extractDummyPronunciation が依存している。
// internal/quizgen/prompt_golden_test.go が JS 側の文字列と突き合わせている。

// dummyReasonFormat はダミー理由の書式。
//
// 「語（ローマ字 / 意味）：理由」の形は変えられない。extractDummyPronunciation が
// この括弧とスラッシュから選択肢の発音を切り出しており、崩すと4択の発音表示が空になる。
// en 版も同じ形（半角括弧とスラッシュ）を保つこと。
var dummyReasonFormat = map[lang.Lang]string{
	lang.JA: `dummy_reasons: 各ダミーを「単語（ローマ字 / 日本語）：不正解理由」の形式で1行ずつ書く`,
	lang.EN: `dummy_reasons: 各ダミーを "word (romaji / English meaning): reason" の形式で1行ずつ書く`,
}

var explanationRule = map[lang.Lang]string{
	lang.JA: `explanation: correct_answer が入る理由だけを日本語で簡潔に書く。ダミーには触れない`,
	lang.EN: `explanation: correct_answer が入る理由だけを英語で簡潔に書く。ダミーには触れない`,
}

// visibilityRule は「訳文を見なくても解ける問題にする」という制約。
// 日本語版の文言は変えない。
var visibilityRule = map[lang.Lang]string{
	lang.JA: `【最重要ルール】
ヒント表示前に見えるのは blank_text と「correct_answer + dummies」のタイ語だけ。
日本語訳・語句・発音・解説なしでも、周辺タイ語だけで3ダミーを除外できる必要がある。`,
	lang.EN: `【最重要ルール】
ヒント表示前に見えるのは blank_text と「correct_answer + dummies」のタイ語だけ。
訳文・語句・発音・解説なしでも、周辺タイ語だけで3ダミーを除外できる必要がある。`,
}

var translationOnlyRule = map[lang.Lang]string{
	lang.JA: `- 日本語訳、話者性別、敬意、人称だけで区別する語は不可`,
	lang.EN: `- 訳文、話者性別、敬意、人称だけで区別する語は不可`,
}

// bannedReasonPhrases は禁止表現。出力言語の文字列でないと機能しない
// （生成物に対する検査語なので）。日本語ルールの英訳移植ではなく、
// 同じ「逃げ道」を英語で塞いだもの。
var bannedReasonPhrases = map[lang.Lang]string{
	lang.JA: `【理由の禁止表現】
dummy_reasons に「元の文」「文脈」「質問文」「合わない」「意味が異なる」「別の意味になる」「より一般的」は書かない。
「〜を示す文脈には合わない」「こちらの方が自然」と説明したくなる候補は、意味上入りうるため不可。`,
	lang.EN: `【理由の禁止表現】
dummy_reasons に "the original sentence" / "context" / "the question" / "does not fit" /
"a different meaning" / "means something else" / "more common" / "more natural" は書かない。
"does not fit the context of ..." や "this one is more natural" と説明したくなる候補は、意味上入りうるため不可。`,
}

var goodReasonExamples = map[lang.Lang]string{
	lang.JA: `【良い理由例】
- แกง（kɛɛng / カレー）：動詞の位置に名詞が入り文法上不自然
- เบื่อ（bʉ̀a / 飽きる）：目的語の位置に動詞が入り文法上不自然
- เสื้อ（sʉ̂a / 服）：移動動詞の目的語に衣類名詞が入り不自然
- ช้า（cháa / 遅い）：目的語に形容詞が入り不自然
- สอง（sɔ̌ɔng / 二）：場所を示す前置詞句に数詞が入り不自然`,
	lang.EN: `【良い理由例】
- แกง (kɛɛng / curry): a noun in a verb slot is ungrammatical
- เบื่อ (bʉ̀a / to be bored): a verb in an object slot is ungrammatical
- เสื้อ (sʉ̂a / shirt): a clothing noun cannot be the object of a motion verb
- ช้า (cháa / slow): an adjective cannot fill an object slot
- สอง (sɔ̌ɔng / two): a numeral cannot fill a locative prepositional phrase`,
}

const systemPromptTemplate = `確定済みのタイ語穴埋め問題1問について、ダミー選択肢・理由・解説だけを作成してください。
blank_text と correct_answer は変更しません。

【出力】
dummies / explanation / dummy_reasons の3項目のみ。
- dummies: correct_answer 以外のタイ語3件
- {{EXPLANATION_RULE}}
- {{DUMMY_REASON_FORMAT}}

{{VISIBILITY_RULE}}

【ダミー条件】
- 品詞不一致、項構造不一致、対象カテゴリ不一致など、局所的に破綻する語を選ぶ
- 代入して文法上/意味上入りうる語、意味違いだけの語、同カテゴリ置換は不可
{{TRANSLATION_ONLY_RULE}}
- 類別詞・指示詞・代名詞・語気助詞・前置詞など、複数候補が成立しやすい機能語同士をダミーにしない
- 正解が類別詞の場合、他の類別詞ではなく、動詞・形容詞・場所名詞など別品詞を優先する
- dummy_reasons の3行は互いに異なる理由にする。同じ理由になる候補は差し替える

{{BANNED_REASON_PHRASES}}

【NG例】
- กิน___ → ข้าว/ผัก/เนื้อ は全て目的語として成立
- อยู่___กล่อง → ใน/บน/ใต้/ข้าง は全て位置関係として成立
- ___ไปตลาด → ผม/ฉัน/เรา/เขา は話者情報なしでは一意に選べない
- โรงแรม___ดีนะ → นี้/นั้น/นั่น は指示詞として複数成立
- ___นี้แพงไปไหม → ลูก/อัน/ตัว は類別詞として複数成立
- ฉันมีแมวสอง___ → ตัว/ตน は分類だけで落とす問題として曖昧

{{GOOD_REASON_EXAMPLES}}

【最終確認】
dummies 3件、correct_answer 不含、dummy_reasons 3件。
3ダミーすべて、周辺タイ語だけで除外できること。`

// SystemPrompt は言語ごとのシステムプロンプト。
func SystemPrompt(l lang.Lang) string {
	if l != lang.EN {
		l = lang.JA
	}
	return strings.NewReplacer(
		"{{EXPLANATION_RULE}}", explanationRule[l],
		"{{DUMMY_REASON_FORMAT}}", dummyReasonFormat[l],
		"{{VISIBILITY_RULE}}", visibilityRule[l],
		"{{TRANSLATION_ONLY_RULE}}", translationOnlyRule[l],
		"{{BANNED_REASON_PHRASES}}", bannedReasonPhrases[l],
		"{{GOOD_REASON_EXAMPLES}}", goodReasonExamples[l],
	).Replace(systemPromptTemplate)
}

// BuildPrompt はユーザープロンプト（問題データの並び）を組み立てる。
func BuildPrompt(sentences []QuizSentenceSeed, l lang.Lang) string {
	return "以下のタイ語穴埋め問題について、システム指示に従って出力してください。\n\n" +
		buildPreparedSentenceList(sentences, l)
}

func buildPreparedSentenceList(sentences []QuizSentenceSeed, l lang.Lang) string {
	prepared := PrepareInputs(sentences)

	// japanese_translation の中身は lang に従った訳文（フィールド名だけが据え置き）。
	// ラベルまで「日本語訳」のままだと、英訳を日本語だと言って渡すことになる。
	translationLabel := "日本語訳"
	if l == lang.EN {
		translationLabel = "translation"
	}

	entries := make([]string, 0, len(prepared))
	for i, s := range prepared {
		meaning := s.CorrectAnswerMeaning
		if meaning == "" {
			meaning = "未指定"
		}
		entries = append(entries, fmt.Sprintf(
			"%d. thai_text: %s\n   blank_text: %s\n   correct_answer: %s\n"+
				"   correct_answer_pronunciation: %s\n   correct_answer_meaning: %s\n   %s: %s",
			i+1, s.ThaiText, s.BlankText, s.CorrectAnswer,
			s.Pronunciation, meaning, translationLabel, s.JapaneseTranslation))
	}
	return strings.Join(entries, "\n\n")
}
