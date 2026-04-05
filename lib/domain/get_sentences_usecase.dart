import '../data/models/thai_sentence.dart';
import '../data/sentence_repository.dart';

/// Use case for retrieving Thai sentences from the database
class GetSentencesUseCase {
  final SentenceRepository _repository;

  GetSentencesUseCase(this._repository);

  /// Get all sentences from the database
  ///
  /// Returns a list of [ThaiSentence] ordered by creation date (newest first)
  /// Throws [GetSentencesException] if retrieval fails
  Future<List<ThaiSentence>> execute() async {
    try {
      return await _repository.getAllSentences();
    } on RepositoryException catch (e) {
      throw GetSentencesException('Failed to get sentences: ${e.message}');
    } catch (e) {
      throw GetSentencesException('Failed to get sentences: $e');
    }
  }

  /// Get the most recent sentence
  ///
  /// Returns the most recent [ThaiSentence] if available, null otherwise
  /// Throws [GetSentencesException] if retrieval fails
  Future<ThaiSentence?> getMostRecent() async {
    try {
      return await _repository.getMostRecentSentence();
    } on RepositoryException catch (e) {
      throw GetSentencesException(
          'Failed to get most recent sentence: ${e.message}');
    } catch (e) {
      throw GetSentencesException('Failed to get most recent sentence: $e');
    }
  }

  /// Get total sentence count
  ///
  /// Returns the total number of sentences in the database
  /// Throws [GetSentencesException] if count fails
  Future<int> getCount() async {
    try {
      return await _repository.getSentenceCount();
    } on RepositoryException catch (e) {
      throw GetSentencesException('Failed to get sentence count: ${e.message}');
    } catch (e) {
      throw GetSentencesException('Failed to get sentence count: $e');
    }
  }

  /// Check if there are any sentences in the database
  Future<bool> hasSentences() async {
    try {
      final count = await getCount();
      return count > 0;
    } catch (e) {
      return false;
    }
  }
}

/// Exception thrown when sentence retrieval fails
class GetSentencesException implements Exception {
  final String message;

  GetSentencesException(this.message);

  /// Get user-friendly error message
  String getUserMessage() {
    return 'データの読み込みに失敗しました。もう一度お試しください。';
  }

  @override
  String toString() => 'GetSentencesException: $message';
}
