export interface Syllable {
  text: string;
}

export interface WordBreakdown {
  word: string;
  pronunciation: string;
  meaning: string;
  grammatical_role?: string;
  syllables?: Syllable[];
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
}

export interface GenerateSentenceResponse {
  success: boolean;
  data?: ThaiSentence;
  error?: {
    code: string;
    message: string;
  };
}
