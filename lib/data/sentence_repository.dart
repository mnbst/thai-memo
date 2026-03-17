// =============================================================================
// sentence_repository.dart
// 例文リポジトリ。
// ローカルDB（SQLite）とリモートAPI（Cloud Functions）の間を仲介するリポジトリ層。
// Clean Architectureにおけるデータ層の中心。
//
// 主な責務:
//   - バックエンドAPIから例文を生成し、ローカルDBに保存
//   - ローカルDBからの例文取得（全件、最新、お気に入り）
//   - お気に入りのトグル、例文の削除
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

  /// Generate a new sentence from backend API and save it to database
  Future<ThaiSentence> generateAndSaveSentence({
    Map<String, String?> generationParams = const {},
  }) async {
    try {
      // Ensure user is authenticated
      await _authService.ensureAuthenticated();

      // Generate sentence from backend API (no API key needed)
      final sentence = await _apiService.generateSentence(
        generationParams: generationParams,
      );

      // Add ID and assign sentence IDs to word breakdowns
      final sentenceId = _uuid.v4();
      final sentenceWithId = sentence.copyWith(id: sentenceId);

      final wordBreakdownsWithIds = sentence.wordBreakdowns.map((wb) {
        return wb.copyWith(
          id: _uuid.v4(),
          sentenceId: sentenceId,
        );
      }).toList();

      final finalSentence = sentenceWithId.copyWith(
        wordBreakdowns: wordBreakdownsWithIds,
      );

      // Save to database
      await saveSentence(finalSentence);

      // Update last generation timestamp
      await _secureStorage.saveLastGenerationTimestamp(DateTime.now());

      // Log successful generation
      await _logGeneration(success: true, tokensUsed: null);

      return finalSentence;
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

  /// 残りクォータ分の例文を一括生成して保存
  Future<List<ThaiSentence>> generateAndSaveBatchSentences() async {
    try {
      await _authService.ensureAuthenticated();

      final sentences = await _apiService.generateBatchSentences();

      final savedSentences = <ThaiSentence>[];
      for (final sentence in sentences) {
        final sentenceId = _uuid.v4();
        final sentenceWithId = sentence.copyWith(id: sentenceId);
        final wordBreakdownsWithIds = sentence.wordBreakdowns.map((wb) {
          return wb.copyWith(id: _uuid.v4(), sentenceId: sentenceId);
        }).toList();
        final finalSentence = sentenceWithId.copyWith(
          wordBreakdowns: wordBreakdownsWithIds,
        );
        await saveSentence(finalSentence);
        savedSentences.add(finalSentence);
      }

      await _secureStorage.saveLastGenerationTimestamp(DateTime.now());
      await _logGeneration(success: true, tokensUsed: null);

      return savedSentences;
    } on BackendApiException catch (e) {
      await _logGeneration(success: false, errorMessage: e.message, tokensUsed: null);
      rethrow;
    } catch (e) {
      await _logGeneration(success: false, errorMessage: e.toString(), tokensUsed: null);
      throw RepositoryException('Failed to generate batch sentences: $e');
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

  /// Get favorite sentences
  Future<List<ThaiSentence>> getFavoriteSentences() async {
    try {
      final sentenceMaps = await _databaseHelper.getFavoriteSentences();
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
      throw RepositoryException('Failed to get favorite sentences: $e');
    }
  }

  /// Toggle favorite status of a sentence
  Future<void> toggleFavorite(String id, bool isFavorite) async {
    try {
      await _databaseHelper.toggleFavorite(id, isFavorite);
    } catch (e) {
      throw RepositoryException('Failed to toggle favorite: $e');
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
