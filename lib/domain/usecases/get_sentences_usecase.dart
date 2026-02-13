import '../../data/models/thai_sentence.dart';
import '../../data/repositories/sentence_repository.dart';

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

  /// Get a specific sentence by ID
  ///
  /// Returns the [ThaiSentence] if found, null otherwise
  /// Throws [GetSentencesException] if retrieval fails
  Future<ThaiSentence?> getById(String id) async {
    try {
      return await _repository.getSentenceById(id);
    } on RepositoryException catch (e) {
      throw GetSentencesException('Failed to get sentence: ${e.message}');
    } catch (e) {
      throw GetSentencesException('Failed to get sentence: $e');
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

  /// Get favorite sentences
  ///
  /// Returns a list of favorite [ThaiSentence]s
  /// Throws [GetSentencesException] if retrieval fails
  Future<List<ThaiSentence>> getFavorites() async {
    try {
      return await _repository.getFavoriteSentences();
    } on RepositoryException catch (e) {
      throw GetSentencesException(
          'Failed to get favorite sentences: ${e.message}');
    } catch (e) {
      throw GetSentencesException('Failed to get favorite sentences: $e');
    }
  }

  /// Toggle favorite status of a sentence
  ///
  /// [id] is the sentence ID
  /// [isFavorite] is the new favorite status
  /// Throws [GetSentencesException] if update fails
  Future<void> toggleFavorite(String id, bool isFavorite) async {
    try {
      await _repository.toggleFavorite(id, isFavorite);
    } on RepositoryException catch (e) {
      throw GetSentencesException('Failed to toggle favorite: ${e.message}');
    } catch (e) {
      throw GetSentencesException('Failed to toggle favorite: $e');
    }
  }

  /// Delete a sentence
  ///
  /// [id] is the sentence ID to delete
  /// Throws [GetSentencesException] if deletion fails
  Future<void> delete(String id) async {
    try {
      await _repository.deleteSentence(id);
    } on RepositoryException catch (e) {
      throw GetSentencesException('Failed to delete sentence: ${e.message}');
    } catch (e) {
      throw GetSentencesException('Failed to delete sentence: $e');
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
