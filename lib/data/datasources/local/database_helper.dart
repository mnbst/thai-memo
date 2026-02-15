import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/config/app_config.dart';
import '../../../core/constants/database_constants.dart';

/// Database helper class for managing SQLite database operations
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

  /// Get favorite sentences
  Future<List<Map<String, dynamic>>> getFavoriteSentences() async {
    final db = await database;
    return await db.query(
      DatabaseConstants.tableSentences,
      where: '${DatabaseConstants.columnIsFavorite} = ?',
      whereArgs: [1],
      orderBy: '${DatabaseConstants.columnCreatedAt} DESC',
    );
  }

  /// Update a sentence
  Future<int> updateSentence(
      String id, Map<String, dynamic> sentence) async {
    final db = await database;
    return await db.update(
      DatabaseConstants.tableSentences,
      sentence,
      where: '${DatabaseConstants.columnSentenceId} = ?',
      whereArgs: [id],
    );
  }

  /// Toggle favorite status of a sentence
  Future<int> toggleFavorite(String id, bool isFavorite) async {
    final db = await database;
    return await db.update(
      DatabaseConstants.tableSentences,
      {DatabaseConstants.columnIsFavorite: isFavorite ? 1 : 0},
      where: '${DatabaseConstants.columnSentenceId} = ?',
      whereArgs: [id],
    );
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

  /// Delete all word breakdowns for a sentence
  Future<int> deleteWordBreakdownsBySentenceId(String sentenceId) async {
    final db = await database;
    return await db.delete(
      DatabaseConstants.tableWordBreakdowns,
      where: '${DatabaseConstants.columnWordSentenceId} = ?',
      whereArgs: [sentenceId],
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

  /// Get all generation logs
  Future<List<Map<String, dynamic>>> getAllGenerationLogs() async {
    final db = await database;
    return await db.query(
      DatabaseConstants.tableGenerationLogs,
      orderBy: '${DatabaseConstants.columnGeneratedAt} DESC',
    );
  }

  /// Get generation logs with pagination
  Future<List<Map<String, dynamic>>> getGenerationLogs(
      int limit, int offset) async {
    final db = await database;
    return await db.query(
      DatabaseConstants.tableGenerationLogs,
      orderBy: '${DatabaseConstants.columnGeneratedAt} DESC',
      limit: limit,
      offset: offset,
    );
  }

  /// Get the most recent generation log
  Future<Map<String, dynamic>?> getMostRecentGenerationLog() async {
    final db = await database;
    final results = await db.query(
      DatabaseConstants.tableGenerationLogs,
      orderBy: '${DatabaseConstants.columnGeneratedAt} DESC',
      limit: 1,
    );
    return results.isNotEmpty ? results.first : null;
  }

  /// Get total number of successful generations
  Future<int> getSuccessfulGenerationCount() async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM ${DatabaseConstants.tableGenerationLogs} '
      'WHERE ${DatabaseConstants.columnSuccess} = 1',
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Get total tokens used
  Future<int> getTotalTokensUsed() async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT SUM(${DatabaseConstants.columnApiTokensUsed}) as total '
      'FROM ${DatabaseConstants.tableGenerationLogs}',
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  // ==================== App Settings CRUD Operations ====================

  /// Set an app setting
  Future<int> setSetting(String key, String value) async {
    final db = await database;
    return await db.insert(
      DatabaseConstants.tableAppSettings,
      {
        DatabaseConstants.columnSettingKey: key,
        DatabaseConstants.columnSettingValue: value,
        DatabaseConstants.columnUpdatedAt: DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Get an app setting
  Future<String?> getSetting(String key) async {
    final db = await database;
    final results = await db.query(
      DatabaseConstants.tableAppSettings,
      where: '${DatabaseConstants.columnSettingKey} = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (results.isNotEmpty) {
      return results.first[DatabaseConstants.columnSettingValue] as String?;
    }
    return null;
  }

  /// Delete a setting
  Future<int> deleteSetting(String key) async {
    final db = await database;
    return await db.delete(
      DatabaseConstants.tableAppSettings,
      where: '${DatabaseConstants.columnSettingKey} = ?',
      whereArgs: [key],
    );
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

  /// Close the database
  Future<void> close() async {
    final db = await database;
    await db.close();
  }

  /// Delete the entire database (for testing or reset)
  Future<void> deleteDatabase() async {
    String path = join(await getDatabasesPath(), AppConfig.databaseName);
    await databaseFactory.deleteDatabase(path);
    _database = null;
  }

  /// Get database statistics
  Future<Map<String, dynamic>> getDatabaseStats() async {
    final sentenceCount = await getSentenceCount();
    final successfulGenerations = await getSuccessfulGenerationCount();
    final totalTokens = await getTotalTokensUsed();

    return {
      'sentence_count': sentenceCount,
      'successful_generations': successfulGenerations,
      'total_tokens_used': totalTokens,
    };
  }
}
