/// Database-related constants
class DatabaseConstants {
  DatabaseConstants._();

  // ==================== Table Names ====================
  static const String tableSentences = 'sentences';
  static const String tableWordBreakdowns = 'word_breakdowns';
  static const String tableGenerationLogs = 'generation_logs';
  static const String tableAppSettings = 'app_settings';

  // ==================== Sentences Table ====================
  static const String columnSentenceId = 'id';
  static const String columnThaiText = 'thai_text';
  static const String columnPronunciation = 'pronunciation';
  static const String columnJapaneseTranslation = 'japanese_translation';
  static const String columnContextExplanation = 'context_explanation';
  static const String columnSituation = 'situation';
  static const String columnEmotion = 'emotion';
  static const String columnUsageScenarios = 'usage_scenarios';
  static const String columnCreatedAt = 'created_at';
  static const String columnIsFavorite = 'is_favorite';

  // ==================== Word Breakdowns Table ====================
  static const String columnWordId = 'id';
  static const String columnWordSentenceId = 'sentence_id';
  static const String columnWordText = 'word_text';
  static const String columnWordPronunciation = 'pronunciation';
  static const String columnWordMeaning = 'meaning';
  static const String columnGrammaticalRole = 'grammatical_role';
  static const String columnWordOrder = 'word_order';
  static const String columnSyllablesJson = 'syllables_json';

  // ==================== Generation Logs Table ====================
  static const String columnLogId = 'id';
  static const String columnGeneratedAt = 'generated_at';
  static const String columnSuccess = 'success';
  static const String columnErrorMessage = 'error_message';
  static const String columnApiTokensUsed = 'api_tokens_used';

  // ==================== App Settings Table ====================
  static const String columnSettingKey = 'key';
  static const String columnSettingValue = 'value';
  static const String columnUpdatedAt = 'updated_at';

  // ==================== SQL Statements ====================

  /// Create sentences table
  static const String createSentencesTable = '''
    CREATE TABLE $tableSentences (
      $columnSentenceId TEXT PRIMARY KEY,
      $columnThaiText TEXT NOT NULL,
      $columnPronunciation TEXT NOT NULL,
      $columnJapaneseTranslation TEXT NOT NULL,
      $columnContextExplanation TEXT NOT NULL,
      $columnSituation TEXT,
      $columnEmotion TEXT,
      $columnUsageScenarios TEXT,
      $columnCreatedAt INTEGER NOT NULL,
      $columnIsFavorite INTEGER DEFAULT 0
    )
  ''';

  /// Create word_breakdowns table
  static const String createWordBreakdownsTable = '''
    CREATE TABLE $tableWordBreakdowns (
      $columnWordId TEXT PRIMARY KEY,
      $columnWordSentenceId TEXT NOT NULL,
      $columnWordText TEXT NOT NULL,
      $columnWordPronunciation TEXT NOT NULL,
      $columnWordMeaning TEXT NOT NULL,
      $columnGrammaticalRole TEXT,
      $columnWordOrder INTEGER NOT NULL,
      $columnSyllablesJson TEXT,
      FOREIGN KEY ($columnWordSentenceId)
        REFERENCES $tableSentences($columnSentenceId)
        ON DELETE CASCADE
    )
  ''';

  /// Create generation_logs table
  static const String createGenerationLogsTable = '''
    CREATE TABLE $tableGenerationLogs (
      $columnLogId TEXT PRIMARY KEY,
      $columnGeneratedAt INTEGER NOT NULL,
      $columnSuccess INTEGER NOT NULL,
      $columnErrorMessage TEXT,
      $columnApiTokensUsed INTEGER
    )
  ''';

  /// Create app_settings table
  static const String createAppSettingsTable = '''
    CREATE TABLE $tableAppSettings (
      $columnSettingKey TEXT PRIMARY KEY,
      $columnSettingValue TEXT NOT NULL,
      $columnUpdatedAt INTEGER NOT NULL
    )
  ''';

  /// Create index for sentences by created_at
  static const String createIndexSentencesCreatedAt = '''
    CREATE INDEX idx_sentences_created_at
    ON $tableSentences($columnCreatedAt DESC)
  ''';

  /// Create index for word_breakdowns by sentence_id
  static const String createIndexWordBreakdownsSentenceId = '''
    CREATE INDEX idx_word_breakdowns_sentence_id
    ON $tableWordBreakdowns($columnWordSentenceId)
  ''';

  /// Create index for generation_logs by generated_at
  static const String createIndexGenerationLogsGeneratedAt = '''
    CREATE INDEX idx_generation_logs_generated_at
    ON $tableGenerationLogs($columnGeneratedAt DESC)
  ''';

  /// List of all create table statements
  static const List<String> createTableStatements = [
    createSentencesTable,
    createWordBreakdownsTable,
    createGenerationLogsTable,
    createAppSettingsTable,
  ];

  /// List of all create index statements
  static const List<String> createIndexStatements = [
    createIndexSentencesCreatedAt,
    createIndexWordBreakdownsSentenceId,
    createIndexGenerationLogsGeneratedAt,
  ];
}
