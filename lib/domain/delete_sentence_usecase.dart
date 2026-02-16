import '../data/sentence_repository.dart';

/// Use case for deleting sentences
class DeleteSentenceUseCase {
  final SentenceRepository _repository;

  DeleteSentenceUseCase(this._repository);

  /// Delete a single sentence by ID
  Future<void> execute(String id) async {
    try {
      await _repository.deleteSentence(id);
    } on RepositoryException catch (e) {
      throw DeleteSentenceException(e.message);
    } catch (e) {
      throw DeleteSentenceException('Failed to delete sentence: $e');
    }
  }

  /// Delete all sentences
  Future<void> deleteAll() async {
    try {
      await _repository.deleteAllSentences();
    } on RepositoryException catch (e) {
      throw DeleteSentenceException(e.message);
    } catch (e) {
      throw DeleteSentenceException('Failed to delete all sentences: $e');
    }
  }
}

/// Exception for delete sentence operations
class DeleteSentenceException implements Exception {
  final String message;

  DeleteSentenceException(this.message);

  @override
  String toString() => 'DeleteSentenceException: $message';
}
