/// API-related constants
class ApiConstants {
  ApiConstants._();

  /// HTTP headers
  static const String headerContentType = 'Content-Type';
  static const String headerAuthorization = 'Authorization';
  static const String contentTypeJson = 'application/json';

  /// HTTP methods
  static const String methodPost = 'POST';
  static const String methodGet = 'GET';

  /// API response keys
  static const String keyChoices = 'choices';
  static const String keyMessage = 'message';
  static const String keyContent = 'content';
  static const String keyUsage = 'usage';
  static const String keyTotalTokens = 'total_tokens';
  static const String keyError = 'error';
  static const String keyErrorMessage = 'message';

  /// OpenAI roles
  static const String roleSystem = 'system';
  static const String roleUser = 'user';
  static const String roleAssistant = 'assistant';

  /// Error messages
  static const String errorNetworkFailure = 'Network connection failed';
  static const String errorInvalidApiKey = 'Invalid API key';
  static const String errorRateLimit = 'Rate limit exceeded';
  static const String errorServerError = 'Server error occurred';
  static const String errorInvalidResponse = 'Invalid response format';
  static const String errorTimeout = 'Request timeout';
  static const String errorUnknown = 'An unknown error occurred';

  /// Thai sentence generation prompt
  static String get sentenceGenerationPrompt => '''
あなたは日本語話者向けに日々の練習文を作るタイ語教師です。

学習に必要な情報を含むタイ語の新しい文を1つ、JSON形式で生成してください。

要件:
1. 文は日常会話で実用的な内容にする
2. 難易度は中級（簡単すぎず難しすぎない）
3. 必要に応じて文化的背景も含める
4. 話題はあいさつ、食べ物、旅行、感情、仕事、家族などを幅広くする

次の形式の有効なJSONのみを返してください:

{
  "thai_text": "タイ語の文",
  "pronunciation": "発音（ローマ字）(e.g., ไม่รู้สิ = mâi rúu sì, เหมือนกัน = mʉ̌ʉan kan, แหละ = lɛ̀)"",
  "japanese_translation": "日本語訳",
  "word_breakdown": [
    {
      "word": "タイ語の単語",
      "pronunciation": "単語の発音（ローマ字）",
      "meaning": "単語の日本語の意味",
      "grammatical_role": "品詞（例: 名詞, 動詞, 形容詞, 助詞）"
    }
  ],
  "context": {
    "situation": "この表現を使う場面・場所",
    "emotion": "感情・トーン（フォーマル/カジュアル/丁寧/親しみ）",
    "usage_scenarios": "具体的に使えるシチュエーション",
    "cultural_notes": "文化的背景やニュアンス"
  }
}

今すぐ重複しない新しい文を生成してください。
''';
}
