/// Database-related constants
class DatabaseConstants {
  DatabaseConstants._();

  // ==================== Table Names ====================
  static const String tableSentences = 'sentences';
  static const String tableWordBreakdowns = 'word_breakdowns';
  static const String tableGenerationLogs = 'generation_logs';
  static const String tableQuizResults = 'quiz_results';
  static const String tableQuizStats = 'quiz_stats';

  // ==================== Sentences Table ====================
  static const String columnSentenceId = 'id';
  static const String columnThaiText = 'thai_text';
  static const String columnPronunciation = 'pronunciation';
  static const String columnJapaneseTranslation = 'japanese_translation';
  static const String columnContextExplanation = 'context_explanation';
  static const String columnTopic = 'topic';
  static const String columnStyle = 'style';
  static const String columnEmotion = 'emotion';
  static const String columnUsageScenarios = 'usage_scenarios';
  static const String columnCreatedAt = 'created_at';
  static const String columnGenerationTier = 'generation_tier';
  static const String columnTargetWords = 'target_words';
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
  static const String columnWordNotes = 'notes';

  // ==================== Generation Logs Table ====================
  static const String columnLogId = 'id';
  static const String columnGeneratedAt = 'generated_at';
  static const String columnSuccess = 'success';
  static const String columnErrorMessage = 'error_message';
  static const String columnApiTokensUsed = 'api_tokens_used';

  // ==================== Quiz Results Table ====================
  static const String columnQuizResultId = 'id';
  static const String columnQuizSentenceId = 'sentence_id';
  static const String columnQuizQuestionText = 'question_text';
  static const String columnQuizCorrectAnswer = 'correct_answer';
  static const String columnQuizUserAnswer = 'user_answer';
  static const String columnQuizIsCorrect = 'is_correct';
  static const String columnQuizAnsweredAt = 'answered_at';

  // ==================== Quiz Stats Table ====================
  static const String columnStatsId = 'id';
  static const String columnStatsTotalAnswered = 'total_answered';
  static const String columnStatsTotalCorrect = 'total_correct';
  static const String columnStatsCurrentStreak = 'current_streak';
  static const String columnStatsBestStreak = 'best_streak';
  static const String columnStatsLastQuizDate = 'last_quiz_date';
  static const String columnStatsUpdatedAt = 'updated_at';

  // ==================== Daily Activity Table ====================
  static const String tableDailyActivity = 'daily_activity';
  static const String columnActivityDate = 'date';
  static const String columnGenerationDone = 'generation_done';
  static const String columnQuizDone = 'quiz_done';

  // ==================== Streak Stats Table ====================
  static const String tableStreakStats = 'streak_stats';
  static const String columnStreakId = 'id';
  static const String columnStreakCurrent = 'current_streak';
  static const String columnStreakBest = 'best_streak';
  static const String columnStreakLastCompletedDate = 'last_completed_date';
  static const String columnStreakUpdatedAt = 'updated_at';

  // ==================== Pronunciation Attempts Table ====================
  static const String tablePronunciationAttempts = 'pronunciation_attempts';
  static const String columnPronunciationId = 'id';
  static const String columnPronunciationSentenceId = 'sentence_id';
  static const String columnPronunciationAttemptedAt = 'attempted_at';
  static const String columnPronunciationScore = 'overall_score';

  // ==================== Tone Stats Table ====================
  /// 声調別の当たり外れ。「上昇声が苦手」レポートの原資。
  static const String tableToneStats = 'tone_stats';
  static const String columnToneStatsTone = 'tone';
  static const String columnToneStatsAttempts = 'attempts';
  static const String columnToneStatsCorrect = 'correct';
  static const String columnToneStatsUpdatedAt = 'updated_at';

  // ==================== Speaker Pitch Profile Table ====================
  /// 録音を跨いで蓄積する声域。UIに出さない暗黙のキャリブレーション。
  static const String tableSpeakerPitchProfile = 'speaker_pitch_profile';
  static const String columnProfileId = 'id';
  static const String columnProfileMedianSemitone = 'median_semitone';
  static const String columnProfileRangeSemitone = 'range_semitone';
  static const String columnProfileSampleCount = 'sample_count';

  // ==================== SQL Statements ====================

  /// Create sentences table
  static const String createSentencesTable = '''
    CREATE TABLE $tableSentences (
      $columnSentenceId TEXT PRIMARY KEY,
      $columnThaiText TEXT NOT NULL,
      $columnPronunciation TEXT NOT NULL,
      $columnJapaneseTranslation TEXT NOT NULL,
      $columnContextExplanation TEXT NOT NULL,
      $columnTopic TEXT,
      $columnStyle TEXT,
      $columnEmotion TEXT,
      $columnUsageScenarios TEXT,
      $columnGenerationTier TEXT,
      $columnTargetWords TEXT,
      $columnIsFavorite INTEGER DEFAULT 0,
      $columnCreatedAt INTEGER NOT NULL
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
      $columnWordNotes TEXT,
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

  /// Create quiz_results table
  static const String createQuizResultsTable = '''
    CREATE TABLE $tableQuizResults (
      $columnQuizResultId TEXT PRIMARY KEY,
      $columnQuizSentenceId TEXT NOT NULL,
      $columnQuizQuestionText TEXT NOT NULL,
      $columnQuizCorrectAnswer TEXT NOT NULL,
      $columnQuizUserAnswer TEXT NOT NULL,
      $columnQuizIsCorrect INTEGER NOT NULL,
      $columnQuizAnsweredAt INTEGER NOT NULL
    )
  ''';

  /// Create index for quiz_results by answered_at
  static const String createIndexQuizResultsAnsweredAt = '''
    CREATE INDEX idx_quiz_results_answered_at
    ON $tableQuizResults($columnQuizAnsweredAt DESC)
  ''';

  /// Create quiz_stats table (single row cache)
  static const String createQuizStatsTable = '''
    CREATE TABLE $tableQuizStats (
      $columnStatsId INTEGER PRIMARY KEY DEFAULT 1,
      $columnStatsTotalAnswered INTEGER NOT NULL DEFAULT 0,
      $columnStatsTotalCorrect INTEGER NOT NULL DEFAULT 0,
      $columnStatsCurrentStreak INTEGER NOT NULL DEFAULT 0,
      $columnStatsBestStreak INTEGER NOT NULL DEFAULT 0,
      $columnStatsLastQuizDate TEXT,
      $columnStatsUpdatedAt INTEGER NOT NULL
    )
  ''';

  /// Create daily_activity table
  static const String createDailyActivityTable = '''
    CREATE TABLE $tableDailyActivity (
      $columnActivityDate TEXT PRIMARY KEY,
      $columnGenerationDone INTEGER NOT NULL DEFAULT 0,
      $columnQuizDone INTEGER NOT NULL DEFAULT 0
    )
  ''';

  /// Create streak_stats table (single row cache)
  static const String createStreakStatsTable = '''
    CREATE TABLE $tableStreakStats (
      $columnStreakId INTEGER PRIMARY KEY DEFAULT 1,
      $columnStreakCurrent INTEGER NOT NULL DEFAULT 0,
      $columnStreakBest INTEGER NOT NULL DEFAULT 0,
      $columnStreakLastCompletedDate TEXT,
      $columnStreakUpdatedAt INTEGER NOT NULL
    )
  ''';

  /// Create pronunciation_attempts table
  static const String createPronunciationAttemptsTable = '''
    CREATE TABLE $tablePronunciationAttempts (
      $columnPronunciationId TEXT PRIMARY KEY,
      $columnPronunciationSentenceId TEXT NOT NULL,
      $columnPronunciationAttemptedAt INTEGER NOT NULL,
      $columnPronunciationScore REAL NOT NULL
    )
  ''';

  /// Create index for pronunciation_attempts by attempted_at
  static const String createIndexPronunciationAttemptedAt = '''
    CREATE INDEX idx_pronunciation_attempts_attempted_at
    ON $tablePronunciationAttempts($columnPronunciationAttemptedAt DESC)
  ''';

  /// Create tone_stats table
  static const String createToneStatsTable = '''
    CREATE TABLE $tableToneStats (
      $columnToneStatsTone TEXT PRIMARY KEY,
      $columnToneStatsAttempts INTEGER NOT NULL DEFAULT 0,
      $columnToneStatsCorrect INTEGER NOT NULL DEFAULT 0,
      $columnToneStatsUpdatedAt INTEGER NOT NULL
    )
  ''';

  /// Create speaker_pitch_profile table (single row cache)
  static const String createSpeakerPitchProfileTable = '''
    CREATE TABLE $tableSpeakerPitchProfile (
      $columnProfileId INTEGER PRIMARY KEY DEFAULT 1,
      $columnProfileMedianSemitone REAL NOT NULL,
      $columnProfileRangeSemitone REAL NOT NULL,
      $columnProfileSampleCount INTEGER NOT NULL DEFAULT 0
    )
  ''';

  /// List of all create table statements
  static const List<String> createTableStatements = [
    createSentencesTable,
    createWordBreakdownsTable,
    createGenerationLogsTable,
    createQuizResultsTable,
    createQuizStatsTable,
    createDailyActivityTable,
    createStreakStatsTable,
    createPronunciationAttemptsTable,
    createToneStatsTable,
    createSpeakerPitchProfileTable,
  ];

  /// List of all create index statements
  static const List<String> createIndexStatements = [
    createIndexSentencesCreatedAt,
    createIndexWordBreakdownsSentenceId,
    createIndexGenerationLogsGeneratedAt,
    createIndexQuizResultsAnsweredAt,
    createIndexPronunciationAttemptedAt,
  ];
}
