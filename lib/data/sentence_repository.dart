// =============================================================================
// sentence_repository.dart
// 例文リポジトリ。
// ローカルDB（SQLite）とリモートAPI（Cloud Functions）の間を仲介するリポジトリ層。
// Clean Architectureにおけるデータ層の中心。
//
// 主な責務:
//   - バックエンドAPIから例文を生成し、ローカルDBに保存
//   - ローカルDBからの例文取得（全件、最新）
//   - 例文の削除
//   - 生成ログの記録（成功/失敗）
//   - 最終生成タイムスタンプの更新
// =============================================================================

import 'package:uuid/uuid.dart';

import '../../services/firebase_auth_service.dart';
import 'datasources/local/database_helper.dart';
import 'datasources/local/secure_storage_service.dart';
import 'datasources/backend_api_service.dart';
import 'models/thai_sentence.dart';
import 'models/word_breakdown.dart';

/// タイ語例文のリポジトリ
///
/// ローカルDB（SQLite）とリモートAPI（Cloud Functions）を統合的に管理する。
/// UUIDを生成して例文・単語分解にIDを付与する。
class SentenceRepository {
  final DatabaseHelper _databaseHelper;
  final BackendApiService _apiService;
  final SecureStorageService _secureStorage;
  final FirebaseAuthService _authService;
  final Uuid _uuid = const Uuid();

  SentenceRepository({
    DatabaseHelper? databaseHelper,
    BackendApiService? apiService,
    SecureStorageService? secureStorage,
    FirebaseAuthService? authService,
  })  : _databaseHelper = databaseHelper ?? DatabaseHelper.instance,
        _apiService = apiService ?? BackendApiService(),
        _secureStorage = secureStorage ?? SecureStorageService.instance,
        _authService = authService ?? FirebaseAuthService.instance;

  // ==================== Remote Operations ====================

  /// Generate a set of sentences from backend API and save them to database
  ///
  /// [count] 本をまとめて作る（1セット）。クォータ不足なら取れるぶんだけ返る。
  Future<List<ThaiSentence>> generateAndSaveSentences({
    Map<String, String?> generationParams = const {},
    int count = 1,
  }) async {
    try {
      // Ensure user is authenticated
      await _authService.ensureAuthenticated();

      // Generate sentences from backend API (no API key needed)
      final sentences = await _apiService.generateSentences(
        generationParams: generationParams,
        count: count,
      );

      final saved = <ThaiSentence>[];
      for (final sentence in sentences) {
        // Add ID and assign sentence IDs to word breakdowns
        final sentenceId = _uuid.v4();
        final finalSentence = sentence.copyWith(
          id: sentenceId,
          wordBreakdowns: sentence.wordBreakdowns
              .map((wb) => wb.copyWith(id: _uuid.v4(), sentenceId: sentenceId))
              .toList(),
        );

        saved.add(finalSentence);
      }

      // サーバーはセット全体のクォータを一括消費するため、ローカルも同じ
      // トランザクション境界で保存する。途中失敗で1〜4本だけ残さない。
      await _databaseHelper.insertSentencesWithWordBreakdowns([
        for (final sentence in saved)
          (
            sentence: sentence.toDatabase(),
            wordBreakdowns:
                sentence.wordBreakdowns.map((wb) => wb.toDatabase()).toList(),
          ),
      ]);

      // Update last generation timestamp
      await _secureStorage.saveLastGenerationTimestamp(DateTime.now());

      // Log successful generation
      await _logGeneration(success: true, tokensUsed: null);

      return saved;
    } on BackendApiException catch (e) {
      // Log failed generation
      await _logGeneration(
        success: false,
        errorMessage: e.message,
        tokensUsed: null,
      );
      rethrow;
    } catch (e) {
      // Log failed generation
      await _logGeneration(
        success: false,
        errorMessage: e.toString(),
        tokensUsed: null,
      );
      throw RepositoryException('Failed to generate sentence: $e');
    }
  }

  // ==================== Local Database Operations ====================

  /// Save a sentence to the database
  Future<void> saveSentence(ThaiSentence sentence) async {
    try {
      await _databaseHelper.insertSentenceWithWordBreakdowns(
        sentence: sentence.toDatabase(),
        wordBreakdowns:
            sentence.wordBreakdowns.map((wb) => wb.toDatabase()).toList(),
      );
    } catch (e) {
      throw RepositoryException('Failed to save sentence: $e');
    }
  }

  /// Check whether a sentence is already stored locally
  Future<bool> sentenceExists(String id) async {
    try {
      return await _databaseHelper.sentenceExists(id);
    } catch (e) {
      throw RepositoryException('Failed to check sentence: $e');
    }
  }

  /// Get a sentence by ID from the local database
  Future<ThaiSentence?> getSentenceById(String id) async {
    try {
      final sentenceMap = await _databaseHelper.getSentenceById(id);
      if (sentenceMap == null) return null;

      final wordBreakdownMaps =
          await _databaseHelper.getWordBreakdownsBySentenceId(id);
      final wordBreakdowns = wordBreakdownMaps
          .map((map) => WordBreakdown.fromDatabase(map))
          .toList();

      return ThaiSentence.fromDatabase(sentenceMap, wordBreakdowns);
    } catch (e) {
      throw RepositoryException('Failed to get sentence by ID: $e');
    }
  }

  /// Get all sentences from the database
  Future<List<ThaiSentence>> getAllSentences() async {
    try {
      final sentenceMaps = await _databaseHelper.getAllSentences();
      final sentences = <ThaiSentence>[];

      for (var sentenceMap in sentenceMaps) {
        final sentenceId = sentenceMap['id'] as String;
        final wordBreakdownMaps =
            await _databaseHelper.getWordBreakdownsBySentenceId(sentenceId);

        final wordBreakdowns = wordBreakdownMaps
            .map((map) => WordBreakdown.fromDatabase(map))
            .toList();

        sentences.add(ThaiSentence.fromDatabase(sentenceMap, wordBreakdowns));
      }

      return sentences;
    } catch (e) {
      throw RepositoryException('Failed to get sentences: $e');
    }
  }

  /// Get the most recent sentence
  Future<ThaiSentence?> getMostRecentSentence() async {
    try {
      final sentenceMap = await _databaseHelper.getMostRecentSentence();
      if (sentenceMap == null) return null;

      final sentenceId = sentenceMap['id'] as String;
      final wordBreakdownMaps =
          await _databaseHelper.getWordBreakdownsBySentenceId(sentenceId);
      final wordBreakdowns = wordBreakdownMaps
          .map((map) => WordBreakdown.fromDatabase(map))
          .toList();

      return ThaiSentence.fromDatabase(sentenceMap, wordBreakdowns);
    } catch (e) {
      throw RepositoryException('Failed to get most recent sentence: $e');
    }
  }

  /// Delete a sentence
  Future<void> deleteSentence(String id) async {
    try {
      await _databaseHelper.deleteSentence(id);
    } catch (e) {
      throw RepositoryException('Failed to delete sentence: $e');
    }
  }

  /// Toggle favorite status
  Future<void> toggleFavorite(String id, bool isFavorite) async {
    try {
      await _databaseHelper.updateSentenceFavorite(id, isFavorite);
    } catch (e) {
      throw RepositoryException('Failed to toggle favorite: $e');
    }
  }

  /// Delete all sentences
  Future<void> deleteAllSentences() async {
    try {
      await _databaseHelper.deleteAllSentences();
    } catch (e) {
      throw RepositoryException('Failed to delete all sentences: $e');
    }
  }

  /// Get total sentence count
  Future<int> getSentenceCount() async {
    try {
      return await _databaseHelper.getSentenceCount();
    } catch (e) {
      throw RepositoryException('Failed to get sentence count: $e');
    }
  }

  /// Log a generation attempt
  Future<void> _logGeneration({
    required bool success,
    String? errorMessage,
    int? tokensUsed,
  }) async {
    try {
      final log = {
        'id': _uuid.v4(),
        'generated_at': DateTime.now().millisecondsSinceEpoch,
        'success': success ? 1 : 0,
        'error_message': errorMessage,
        'api_tokens_used': tokensUsed,
      };
      await _databaseHelper.insertGenerationLog(log);
    } catch (e) {
      // Ignore logging errors
    }
  }

  // ==================== Cleanup ====================

  /// Clean up resources
  void dispose() {
    _apiService.dispose();
  }
}

/// Custom exception for repository operations
class RepositoryException implements Exception {
  final String message;

  RepositoryException(this.message);

  @override
  String toString() => 'RepositoryException: $message';
}
