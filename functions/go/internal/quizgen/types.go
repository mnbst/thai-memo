package quizgen

// QuizSentenceSeed はクイズ生成の入力（例文1件ぶん）。
type QuizSentenceSeed struct {
	ThaiText             string `json:"thai_text"`
	Pronunciation        string `json:"pronunciation"`
	JapaneseTranslation  string `json:"japanese_translation"`
	KeyWord              string `json:"key_word"`
	KeyWordPronunciation string `json:"key_word_pronunciation"`
	KeyWordMeaning       string `json:"key_word_meaning"`
}

// PreparedQuizSentenceSeed は穴埋め位置を確定させた入力。
type PreparedQuizSentenceSeed struct {
	SourceIndex          int    `json:"source_index"`
	ThaiText             string `json:"thai_text"`
	BlankText            string `json:"blank_text"`
	CorrectAnswer        string `json:"correct_answer"`
	Pronunciation        string `json:"pronunciation"`
	CorrectAnswerMeaning string `json:"correct_answer_meaning"`
	JapaneseTranslation  string `json:"japanese_translation"`
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
}
