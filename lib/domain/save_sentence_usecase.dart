import '../data/models/thai_sentence.dart';
import '../data/sentence_repository.dart';

/// Use case for saving Thai sentences and managing API keys
class SaveSentenceUseCase {
  final SentenceRepository _repository;

  SaveSentenceUseCase(this._repository);

  /// Save a sentence to the database
  ///
  /// [sentence] is the sentence to save
  /// Throws [SaveSentenceException] if save fails
  Future<void> execute(ThaiSentence sentence) async {
    try {
      await _repository.saveSentence(sentence);
    } on RepositoryException catch (e) {
      throw SaveSentenceException('Failed to save sentence: ${e.message}');
    } catch (e) {
      throw SaveSentenceException('Failed to save sentence: $e');
    }
  }

  // ==================== API Key Management ====================

  /// Save API key to secure storage
  ///
  /// [apiKey] is the Gemini API key
  /// Throws [SaveSentenceException] if save fails or key is invalid
  Future<void> saveApiKey(String apiKey) async {
    // Validate API key
    if (apiKey.isEmpty) {
      throw SaveSentenceException('API key cannot be empty');
    }

    // Basic format validation
    if (!apiKey.trim().startsWith('AI')) {
      throw SaveSentenceException(
        'Invalid API key format. Gemini API keys start with "AI"',
      );
    }

    try {
      await _repository.saveApiKey(apiKey.trim());
    } on RepositoryException catch (e) {
      throw SaveSentenceException('Failed to save API key: ${e.message}');
    } catch (e) {
      throw SaveSentenceException('Failed to save API key: $e');
    }
  }

  /// Get API key from secure storage
  ///
  /// Returns the API key if it exists, null otherwise
  /// Throws [SaveSentenceException] if retrieval fails
  Future<String?> getApiKey() async {
    try {
      return await _repository.getApiKey();
    } on RepositoryException catch (e) {
      throw SaveSentenceException('Failed to get API key: ${e.message}');
    } catch (e) {
      throw SaveSentenceException('Failed to get API key: $e');
    }
  }

  /// Check if API key is configured
  ///
  /// Returns true if API key exists, false otherwise
  Future<bool> hasApiKey() async {
    try {
      return await _repository.hasApiKey();
    } catch (e) {
      return false;
    }
  }

  /// Delete API key from secure storage
  ///
  /// Throws [SaveSentenceException] if deletion fails
  Future<void> deleteApiKey() async {
    try {
      await _repository.deleteApiKey();
    } on RepositoryException catch (e) {
      throw SaveSentenceException('Failed to delete API key: ${e.message}');
    } catch (e) {
      throw SaveSentenceException('Failed to delete API key: $e');
    }
  }

  /// Get masked API key for display (e.g., "AI***...***abc")
  ///
  /// Returns masked version of the API key
  Future<String?> getMaskedApiKey() async {
    try {
      final apiKey = await getApiKey();
      if (apiKey == null || apiKey.isEmpty) return null;

      if (apiKey.length <= 10) {
        return '***';
      }

      // Show first 3 chars and last 3 chars
      final start = apiKey.substring(0, 3);
      final end = apiKey.substring(apiKey.length - 3);
      return '$start***...***$end';
    } catch (e) {
      return null;
    }
  }
}

/// Exception thrown when sentence save operations fail
class SaveSentenceException implements Exception {
  final String message;

  SaveSentenceException(this.message);

  /// Get user-friendly error message
  String getUserMessage() {
    if (message.contains('API key')) {
      return 'APIキーの保存に失敗しました。もう一度お試しください。';
    } else if (message.contains('empty')) {
      return 'APIキーが空です。有効なAPIキーを入力してください。';
    } else if (message.contains('format')) {
      return 'APIキーの形式が正しくありません。GeminiのAPIキーは"AI"で始まります。';
    } else {
      return 'データの保存に失敗しました。もう一度お試しください。';
    }
  }

  @override
  String toString() => 'SaveSentenceException: $message';
}
