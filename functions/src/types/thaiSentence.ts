export interface WordBreakdown {
  word: string;
  pronunciation: string;
  meaning: string;
  grammatical_role?: string;
  syllables?: string[];
}

export interface SentenceContext {
  topic?: string;
  style?: string;
  emotion?: string;
  usage_scenarios?: string;
  cultural_notes?: string;
}

export interface ThaiSentence {
  thai_text: string;
  pronunciation: string;
  japanese_translation: string;
  word_breakdown: WordBreakdown[];
  context?: SentenceContext;
}

export interface GenerateSentenceRequest {
  topic?: string;
  style?: string;
  politeness?: string;
  grammarFocus?: string;
  vocabLevel?: string;
  sentenceLength?: string;
  emotion?: string;
  learningPurpose?: string;
  toneDensity?: string;
}

export interface GenerateSentenceResponse {
  success: boolean;
  data?: ThaiSentence;
  error?: {
    code: string;
    message: string;
  };
}
