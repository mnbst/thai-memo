package quizgen

const (
	FormatClozeChoice   = "cloze_choice"
	FormatMeaningChoice = "meaning_choice"
)

// QuizSentenceSeed はクイズ生成の入力（例文1件ぶん）。
type QuizSentenceSeed struct {
	QuizFormat string `json:"quiz_format,omitempty"`
	ThaiText   string `json:"thai_text"`
	// Words は word_breakdown の語（出現順）。空欄を語の境界に合わせるために使う。
	// 空なら本文の部分一致で位置を決める（語の途中を空欄にしうる）。
	Words                []string `json:"words,omitempty"`
	Pronunciation        string   `json:"pronunciation"`
	JapaneseTranslation  string   `json:"japanese_translation"`
	KeyWord              string   `json:"key_word"`
	KeyWordPronunciation string   `json:"key_word_pronunciation"`
	KeyWordMeaning       string   `json:"key_word_meaning"`
	// MeaningChoices は意味4択の正解を含む4件。例文の word_breakdown から
	// ルールベースで確定し、モデルには変更させない。
	MeaningChoices []string `json:"meaning_choices,omitempty"`
	// FixedDummies は確定済みの穴埋めダミー3件（PickDistractors の結果）。
	// 入っていればモデルはダミーを作らず、理由と解説だけ書く。
	FixedDummies []string `json:"fixed_dummies,omitempty"`
	// FixedDummyPronunciations はダミーの発音（語 → ローマ字）。
	// 選定側（quiz_distractors.go）が NLP で作る。モデルの理由文から
	// 切り出すより確実で、書式が崩れても4択の発音が空にならない。
	FixedDummyPronunciations map[string]string `json:"fixed_dummy_pronunciations,omitempty"`
}

// PreparedQuizSentenceSeed は穴埋め位置を確定させた入力。
type PreparedQuizSentenceSeed struct {
	SourceIndex          int      `json:"source_index"`
	ThaiText             string   `json:"thai_text"`
	BlankText            string   `json:"blank_text"`
	CorrectAnswer        string   `json:"correct_answer"`
	Pronunciation        string   `json:"pronunciation"`
	CorrectAnswerMeaning string   `json:"correct_answer_meaning"`
	JapaneseTranslation  string   `json:"japanese_translation"`
	QuizFormat           string   `json:"quiz_format,omitempty"`
	MeaningChoices       []string `json:"meaning_choices,omitempty"`
	FixedDummies         []string `json:"fixed_dummies,omitempty"`
	// FixedDummyPronunciations は QuizSentenceSeed から持ち越す。
	FixedDummyPronunciations map[string]string `json:"-"`
}

// Draft はモデルが返す3項目。blank_text と correct_answer は
// こちらで確定済みなのでモデルには作らせない。
type Draft struct {
	Dummies      []string `json:"dummies"`
	Explanation  string   `json:"explanation"`
	DummyReasons []string `json:"dummy_reasons"`
}

// GeneratedQuizQuestion はルールベース補正・検査を通したあとの1問。
type GeneratedQuizQuestion struct {
	// SourceIndex は元になった例文の位置。整数でなければ nil。
	SourceIndex           *int     `json:"source_index,omitempty"`
	ThaiText              string   `json:"thai_text"`
	BlankText             string   `json:"blank_text"`
	CorrectAnswer         string   `json:"correct_answer"`
	CorrectAnswerMeaning  string   `json:"correct_answer_meaning"`
	Choices               []string `json:"choices"`
	ChoicePronunciations  []string `json:"choice_pronunciations"`
	Pronunciation         string   `json:"pronunciation"`
	Explanation           string   `json:"explanation"`
	JapaneseTranslation   string   `json:"japanese_translation"`
	SentencePronunciation string   `json:"sentence_pronunciation"`
	DummyReasons          []string `json:"dummy_reasons"`
	// DummyPronunciations は確定ダミーの発音（語 → ローマ字）。
	// 選択肢の発音を組み立てるための内部項目で、クライアントには出さない
	// （出すのは choice_pronunciations の並び）。
	DummyPronunciations map[string]string `json:"-"`
	QuizFormat          string            `json:"quiz_format,omitempty"`
}
