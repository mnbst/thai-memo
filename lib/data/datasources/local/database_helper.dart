// =============================================================================
// database_helper.dart
// SQLiteデータベースの管理クラス。
// アプリのローカルデータ（例文、単語分解、生成ログ、クイズ結果、クイズ統計）を管理する。
// シングルトンパターンで1つのDBインスタンスを共有。
// テーブル定義はDatabaseConstantsクラスに集約されている。
//
// テーブル構成:
//   - sentences: タイ語例文
//   - word_breakdowns: 例文の単語分解（sentencesにFK、CASCADE DELETE）
//   - generation_logs: 例文生成の成功/失敗ログ
//   - quiz_results: クイズの回答結果
//   - quiz_stats: クイズ統計のキャッシュ（1行のみ）
//
// マイグレーション履歴:
//   v1→v2: syllables_jsonカラム追加
//   v2→v3: DB全体リビルド（声調データ修正）
//   v3→v4: situation→topicリネーム、styleカラム追加
//   v4→v5: quiz_resultsテーブル追加
//   v5→v6: quiz_statsテーブル追加
// =============================================================================

import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/config/app_config.dart';
import '../../../core/database_constants.dart';

/// SQLiteデータベースのCRUD操作を管理するヘルパークラス（シングルトン）
class DatabaseHelper {
  DatabaseHelper._privateConstructor();
  static final DatabaseHelper instance = DatabaseHelper._privateConstructor();

  static Database? _database;

  /// Get database instance (singleton)
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  /// Initialize the database
  Future<Database> _initDatabase() async {
    String path = join(await getDatabasesPath(), AppConfig.databaseName);
    return await openDatabase(
      path,
      version: AppConfig.databaseVersion,
      onCreate: _onCreate,
      onConfigure: _onConfigure,
      onUpgrade: _onUpgrade,
    );
  }

  /// Configure database (enable foreign keys)
  Future<void> _onConfigure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
  }

  /// Create tables when database is first created
  Future<void> _onCreate(Database db, int version) async {
    // Create all tables
    for (String statement in DatabaseConstants.createTableStatements) {
      await db.execute(statement);
    }

    // Create all indexes
    for (String statement in DatabaseConstants.createIndexStatements) {
      await db.execute(statement);
    }
  }

  /// Handle database upgrades
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // Migrate from version 1 to 2: Add syllables_json column
    if (oldVersion < 2) {
      await db.execute('''
        ALTER TABLE ${DatabaseConstants.tableWordBreakdowns}
        ADD COLUMN ${DatabaseConstants.columnSyllablesJson} TEXT
      ''');
    }

    // Migrate from version 2 to 3: Rebuild database (maiTri/maiChattawa cleanup)
    if (oldVersion < 3) {
      // Drop all tables (in reverse order due to foreign keys)
      await db.execute('DROP TABLE IF EXISTS ${DatabaseConstants.tableWordBreakdowns}');
      await db.execute('DROP TABLE IF EXISTS ${DatabaseConstants.tableSentences}');
      await db.execute('DROP TABLE IF EXISTS ${DatabaseConstants.tableGenerationLogs}');
      await db.execute('DROP TABLE IF EXISTS app_settings');

      // Recreate all tables
      for (String statement in DatabaseConstants.createTableStatements) {
        await db.execute(statement);
      }

      // Recreate all indexes
      for (String statement in DatabaseConstants.createIndexStatements) {
        await db.execute(statement);
      }
    }

    // Migrate from version 4 to 5: Add quiz_results table
    if (oldVersion < 5) {
      await db.execute(DatabaseConstants.createQuizResultsTable);
      await db.execute(DatabaseConstants.createIndexQuizResultsAnsweredAt);
    }

    // Migrate from version 5 to 6: Add quiz_stats table
    if (oldVersion < 6) {
      await db.execute(DatabaseConstants.createQuizStatsTable);
    }

    // Migrate from version 6 to 7: Add daily_activity + streak_stats tables
    if (oldVersion < 7) {
      await db.execute(DatabaseConstants.createDailyActivityTable);
      await db.execute(DatabaseConstants.createStreakStatsTable);
    }

    // Migrate from version 3 to 4: Rename situation→topic, add style column
    if (oldVersion < 4) {
      await db.execute('''
        ALTER TABLE ${DatabaseConstants.tableSentences}
        RENAME COLUMN situation TO ${DatabaseConstants.columnTopic}
      ''');
      await db.execute('''
        ALTER TABLE ${DatabaseConstants.tableSentences}
        ADD COLUMN ${DatabaseConstants.columnStyle} TEXT
      ''');
    }
  }

  // ==================== Sentences CRUD Operations ====================

  /// Insert a new sentence
  Future<int> insertSentence(Map<String, dynamic> sentence) async {
    final db = await database;
    return await db.insert(
      DatabaseConstants.tableSentences,
      sentence,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Get all sentences ordered by creation date (newest first)
  Future<List<Map<String, dynamic>>> getAllSentences() async {
    final db = await database;
    return await db.query(
      DatabaseConstants.tableSentences,
      orderBy: '${DatabaseConstants.columnCreatedAt} DESC',
    );
  }

  /// Get a sentence by ID
  Future<Map<String, dynamic>?> getSentenceById(String id) async {
    final db = await database;
    final results = await db.query(
      DatabaseConstants.tableSentences,
      where: '${DatabaseConstants.columnSentenceId} = ?',
      whereArgs: [id],
      limit: 1,
    );
    return results.isNotEmpty ? results.first : null;
  }

  /// Get the most recent sentence
  Future<Map<String, dynamic>?> getMostRecentSentence() async {
    final db = await database;
    final results = await db.query(
      DatabaseConstants.tableSentences,
      orderBy: '${DatabaseConstants.columnCreatedAt} DESC',
      limit: 1,
    );
    return results.isNotEmpty ? results.first : null;
  }

  /// Delete a sentence (and its word breakdowns due to CASCADE)
  Future<int> deleteSentence(String id) async {
    final db = await database;
    return await db.delete(
      DatabaseConstants.tableSentences,
      where: '${DatabaseConstants.columnSentenceId} = ?',
      whereArgs: [id],
    );
  }

  /// Delete all sentences (and their word breakdowns due to CASCADE)
  Future<int> deleteAllSentences() async {
    final db = await database;
    return await db.delete(DatabaseConstants.tableSentences);
  }

  /// Get total sentence count
  Future<int> getSentenceCount() async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM ${DatabaseConstants.tableSentences}',
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  // ==================== Word Breakdowns CRUD Operations ====================

  /// Insert a new word breakdown
  Future<int> insertWordBreakdown(Map<String, dynamic> wordBreakdown) async {
    final db = await database;
    return await db.insert(
      DatabaseConstants.tableWordBreakdowns,
      wordBreakdown,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Insert multiple word breakdowns in a transaction
  Future<void> insertWordBreakdowns(
      List<Map<String, dynamic>> wordBreakdowns) async {
    final db = await database;
    final batch = db.batch();
    for (var wordBreakdown in wordBreakdowns) {
      batch.insert(
        DatabaseConstants.tableWordBreakdowns,
        wordBreakdown,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  /// Get word breakdowns for a sentence
  Future<List<Map<String, dynamic>>> getWordBreakdownsBySentenceId(
      String sentenceId) async {
    final db = await database;
    return await db.query(
      DatabaseConstants.tableWordBreakdowns,
      where: '${DatabaseConstants.columnWordSentenceId} = ?',
      whereArgs: [sentenceId],
      orderBy: '${DatabaseConstants.columnWordOrder} ASC',
    );
  }

  // ==================== Generation Logs CRUD Operations ====================

  /// Insert a new generation log
  Future<int> insertGenerationLog(Map<String, dynamic> log) async {
    final db = await database;
    return await db.insert(
      DatabaseConstants.tableGenerationLogs,
      log,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ==================== Quiz Results CRUD Operations ====================

  /// Insert a quiz result
  Future<int> insertQuizResult(Map<String, dynamic> result) async {
    final db = await database;
    return await db.insert(
      DatabaseConstants.tableQuizResults,
      result,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Get quiz stats (total answers and correct count)
  Future<Map<String, int>> getQuizStats() async {
    final db = await database;
    final total = await db.rawQuery(
      'SELECT COUNT(*) as count FROM ${DatabaseConstants.tableQuizResults}',
    );
    final correct = await db.rawQuery(
      'SELECT COUNT(*) as count FROM ${DatabaseConstants.tableQuizResults} '
      'WHERE ${DatabaseConstants.columnQuizIsCorrect} = 1',
    );
    return {
      'total': Sqflite.firstIntValue(total) ?? 0,
      'correct': Sqflite.firstIntValue(correct) ?? 0,
    };
  }

  // ==================== Quiz Stats CRUD Operations ====================

  /// Get cached quiz stats (single row)
  Future<Map<String, dynamic>?> getCachedQuizStats() async {
    final db = await database;
    final results = await db.query(
      DatabaseConstants.tableQuizStats,
      where: '${DatabaseConstants.columnStatsId} = ?',
      whereArgs: [1],
      limit: 1,
    );
    return results.isNotEmpty ? results.first : null;
  }

  /// Update quiz stats cache after a quiz session
  Future<void> updateQuizStats({
    required int sessionCorrect,
    required int sessionTotal,
    required String quizDate,
  }) async {
    final db = await database;
    final existing = await getCachedQuizStats();
    final now = DateTime.now().millisecondsSinceEpoch;

    if (existing == null) {
      // First entry
      await db.insert(DatabaseConstants.tableQuizStats, {
        DatabaseConstants.columnStatsId: 1,
        DatabaseConstants.columnStatsTotalAnswered: sessionTotal,
        DatabaseConstants.columnStatsTotalCorrect: sessionCorrect,
        DatabaseConstants.columnStatsCurrentStreak: 1,
        DatabaseConstants.columnStatsBestStreak: 1,
        DatabaseConstants.columnStatsLastQuizDate: quizDate,
        DatabaseConstants.columnStatsUpdatedAt: now,
      });
      return;
    }

    final prevDate = existing[DatabaseConstants.columnStatsLastQuizDate] as String?;
    final prevStreak = existing[DatabaseConstants.columnStatsCurrentStreak] as int? ?? 0;
    final prevBest = existing[DatabaseConstants.columnStatsBestStreak] as int? ?? 0;

    // Calculate streak
    int newStreak;
    if (prevDate == null) {
      newStreak = 1;
    } else if (_isConsecutiveDay(prevDate, quizDate)) {
      newStreak = prevStreak + 1;
    } else if (prevDate == quizDate) {
      newStreak = prevStreak; // Same day, don't increment
    } else {
      newStreak = 1; // Streak broken
    }

    final newBest = newStreak > prevBest ? newStreak : prevBest;

    await db.update(
      DatabaseConstants.tableQuizStats,
      {
        DatabaseConstants.columnStatsTotalAnswered:
            (existing[DatabaseConstants.columnStatsTotalAnswered] as int? ?? 0) +
                sessionTotal,
        DatabaseConstants.columnStatsTotalCorrect:
            (existing[DatabaseConstants.columnStatsTotalCorrect] as int? ?? 0) +
                sessionCorrect,
        DatabaseConstants.columnStatsCurrentStreak: newStreak,
        DatabaseConstants.columnStatsBestStreak: newBest,
        DatabaseConstants.columnStatsLastQuizDate: quizDate,
        DatabaseConstants.columnStatsUpdatedAt: now,
      },
      where: '${DatabaseConstants.columnStatsId} = ?',
      whereArgs: [1],
    );
  }

  /// Check if two date strings (yyyy-MM-dd) are consecutive days
  bool _isConsecutiveDay(String prev, String current) {
    try {
      final prevDate = DateTime.parse(prev);
      final currDate = DateTime.parse(current);
      final diff = currDate.difference(prevDate).inDays;
      return diff == 1;
    } catch (_) {
      return false;
    }
  }

  // ==================== Transaction Support ====================

  /// Insert a complete sentence with word breakdowns in a transaction
  Future<void> insertSentenceWithWordBreakdowns({
    required Map<String, dynamic> sentence,
    required List<Map<String, dynamic>> wordBreakdowns,
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      // Insert sentence
      await txn.insert(
        DatabaseConstants.tableSentences,
        sentence,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      // Insert word breakdowns
      for (var wordBreakdown in wordBreakdowns) {
        await txn.insert(
          DatabaseConstants.tableWordBreakdowns,
          wordBreakdown,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  // ==================== Utility Methods ====================

  /// Delete the entire database (for testing or reset)
  Future<void> deleteDatabase() async {
    String path = join(await getDatabasesPath(), AppConfig.databaseName);
    await databaseFactory.deleteDatabase(path);
    _database = null;
  }

}
