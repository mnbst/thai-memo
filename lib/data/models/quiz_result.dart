// =============================================================================
// quiz_result.dart
// クイズの回答結果モデル。
// ユーザーがクイズに回答するたびにSQLiteのquiz_resultsテーブルに保存される。
// 正答率の集計やクイズ統計の算出に使用する。
// =============================================================================

import '../../core/database_constants.dart';

/// クイズ回答結果モデル
///
/// 1問ごとの回答記録を保持する。
/// questionText: 出題された穴埋め文
/// correctAnswer: 正解
/// userAnswer: ユーザーの選んだ回答
/// isCorrect: 正解かどうか
class QuizResult {
  final String id;
  final String sentenceId;
  final String questionText;
  final String correctAnswer;
  final String userAnswer;
  final bool isCorrect;
  final DateTime answeredAt;

  const QuizResult({
    required this.id,
    required this.sentenceId,
    required this.questionText,
    required this.correctAnswer,
    required this.userAnswer,
    required this.isCorrect,
    required this.answeredAt,
  });

  factory QuizResult.fromDatabase(Map<String, dynamic> map) => QuizResult(
        id: map[DatabaseConstants.columnQuizResultId] as String,
        sentenceId: map[DatabaseConstants.columnQuizSentenceId] as String,
        questionText: map[DatabaseConstants.columnQuizQuestionText] as String,
        correctAnswer: map[DatabaseConstants.columnQuizCorrectAnswer] as String,
        userAnswer: map[DatabaseConstants.columnQuizUserAnswer] as String,
        isCorrect: (map[DatabaseConstants.columnQuizIsCorrect] as int) == 1,
        answeredAt: DateTime.fromMillisecondsSinceEpoch(
          map[DatabaseConstants.columnQuizAnsweredAt] as int,
        ),
      );

  Map<String, dynamic> toDatabase() => {
        DatabaseConstants.columnQuizResultId: id,
        DatabaseConstants.columnQuizSentenceId: sentenceId,
        DatabaseConstants.columnQuizQuestionText: questionText,
        DatabaseConstants.columnQuizCorrectAnswer: correctAnswer,
        DatabaseConstants.columnQuizUserAnswer: userAnswer,
        DatabaseConstants.columnQuizIsCorrect: isCorrect ? 1 : 0,
        DatabaseConstants.columnQuizAnsweredAt:
            answeredAt.millisecondsSinceEpoch,
      };
}
