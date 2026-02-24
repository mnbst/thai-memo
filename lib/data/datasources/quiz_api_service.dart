import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Firestoreとのクイズ回答同期サービス
class QuizApiService {
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  QuizApiService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  /// 回答結果を Firestore に送信（SRSフィードバック用）
  Future<void> submitAnswer({
    required String sentenceId,
    required bool isCorrect,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return;

    await _firestore
        .collection('users')
        .doc(user.uid)
        .collection('quiz_answers')
        .add({
      'sentence_id': sentenceId,
      'is_correct': isCorrect,
      'answered_at': FieldValue.serverTimestamp(),
    });
  }

  /// クイズセッション完了を Firestore に記録
  Future<void> submitSessionResult({
    required int totalQuestions,
    required int correctCount,
    required String quizQueueId,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return;

    await _firestore
        .collection('users')
        .doc(user.uid)
        .collection('quiz_sessions')
        .add({
      'total_questions': totalQuestions,
      'correct_count': correctCount,
      'quiz_queue_id': quizQueueId,
      'completed_at': FieldValue.serverTimestamp(),
    });
  }
}
