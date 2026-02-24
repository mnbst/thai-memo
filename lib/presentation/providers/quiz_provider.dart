import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/datasources/local/database_helper.dart';
import '../../data/models/quiz_question.dart';
import '../../data/models/quiz_result.dart';

// ==================== State ====================

abstract class QuizState {
  const QuizState();
}

class QuizInitial extends QuizState {
  const QuizInitial();
}

class QuizLoading extends QuizState {
  const QuizLoading();
}

class QuizReady extends QuizState {
  final List<QuizQuestion> questions;
  const QuizReady(this.questions);
}

class QuizAnswering extends QuizState {
  final List<QuizQuestion> questions;
  final int index;
  final List<bool> answers;
  final List<int> selectedIndices;
  const QuizAnswering(this.questions, this.index, this.answers, [this.selectedIndices = const []]);
}

class QuizShowResult extends QuizState {
  final List<QuizQuestion> questions;
  final int index;
  final List<bool> answers;
  final int selectedIndex;
  final bool isCorrect;
  final List<int> selectedIndices;
  const QuizShowResult(
      this.questions, this.index, this.answers, this.selectedIndex, this.isCorrect,
      [this.selectedIndices = const []]);
}

class QuizSummary extends QuizState {
  final List<QuizQuestion> questions;
  final List<bool> answers;
  final int totalCorrect;
  final Map<String, dynamic> stats;
  final List<int> selectedIndices;
  const QuizSummary(this.questions, this.answers, this.totalCorrect, this.stats,
      [this.selectedIndices = const []]);
}

// ==================== Stats Model ====================

class QuizStatsData {
  final int totalAnswered;
  final int totalCorrect;
  final int currentStreak;
  final int bestStreak;
  final int accuracyPercent;

  const QuizStatsData({
    this.totalAnswered = 0,
    this.totalCorrect = 0,
    this.currentStreak = 0,
    this.bestStreak = 0,
    this.accuracyPercent = 0,
  });

  factory QuizStatsData.fromDatabase(Map<String, dynamic>? row) {
    if (row == null) return const QuizStatsData();
    final total = row['total_answered'] as int? ?? 0;
    final correct = row['total_correct'] as int? ?? 0;
    return QuizStatsData(
      totalAnswered: total,
      totalCorrect: correct,
      currentStreak: row['current_streak'] as int? ?? 0,
      bestStreak: row['best_streak'] as int? ?? 0,
      accuracyPercent: total > 0 ? (correct / total * 100).round() : 0,
    );
  }
}

// ==================== Controller ====================

class QuizController extends StateNotifier<QuizState> {
  static const _quizKey = 'quiz_questions';
  static const _quizCompletedKey = 'quiz_completed';
  static const _quizAnswersKey = 'quiz_answers';
  static const _quizSelectedIndicesKey = 'quiz_selected_indices';
  final DatabaseHelper _db = DatabaseHelper.instance;

  QuizController() : super(const QuizInitial());

  /// SharedPrefsからクイズデータを読み込み
  Future<void> loadQuiz() async {
    state = const QuizLoading();

    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_quizKey);

    if (json == null || json.isEmpty) {
      state = const QuizInitial();
      return;
    }

    try {
      final list = jsonDecode(json) as List<dynamic>;
      final questions =
          list.map((e) => QuizQuestion.fromJson(e as Map<String, dynamic>)).toList();
      if (questions.isEmpty) {
        state = const QuizInitial();
        return;
      }

      // 完了済みならサマリーを復元
      if (prefs.getBool(_quizCompletedKey) == true) {
        final answersJson = prefs.getString(_quizAnswersKey);
        final answers = answersJson != null
            ? (jsonDecode(answersJson) as List<dynamic>).cast<bool>()
            : <bool>[];
        final selectedIndicesJson = prefs.getString(_quizSelectedIndicesKey);
        List<int> selectedIndices;
        try {
          selectedIndices = selectedIndicesJson != null
              ? (jsonDecode(selectedIndicesJson) as List<dynamic>)
                  .map((e) => (e as num).toInt())
                  .toList()
              : <int>[];
        } catch (_) {
          selectedIndices = <int>[];
        }
        final totalCorrect = answers.where((a) => a).length;
        final cachedStats = await _db.getCachedQuizStats();
        state = QuizSummary(questions, answers, totalCorrect, cachedStats ?? {}, selectedIndices);
        return;
      }

      state = QuizReady(questions);
    } catch (_) {
      state = const QuizInitial();
    }
  }

  /// クイズ開始
  void startQuiz() {
    if (state is! QuizReady) return;
    final questions = (state as QuizReady).questions;
    state = QuizAnswering(questions, 0, []);
  }

  /// 回答を選択
  Future<void> answerQuestion(int choiceIndex) async {
    if (state is! QuizAnswering) return;
    final s = state as QuizAnswering;
    final question = s.questions[s.index];
    final isCorrect = question.choices[choiceIndex] == question.correctAnswer;
    final newAnswers = [...s.answers, isCorrect];
    final newSelectedIndices = [...s.selectedIndices, choiceIndex];

    // DBに保存
    final result = QuizResult(
      id: '${question.sentenceId}_${DateTime.now().millisecondsSinceEpoch}',
      sentenceId: question.sentenceId,
      questionText: question.blankText,
      correctAnswer: question.correctAnswer,
      userAnswer: question.choices[choiceIndex],
      isCorrect: isCorrect,
      answeredAt: DateTime.now(),
    );
    await _db.insertQuizResult(result.toDatabase());


    state = QuizShowResult(s.questions, s.index, newAnswers, choiceIndex, isCorrect, newSelectedIndices);
  }

  /// 次の問題へ or サマリーへ
  Future<void> nextQuestion() async {
    if (state is! QuizShowResult) return;
    final s = state as QuizShowResult;
    final nextIndex = s.index + 1;

    if (nextIndex >= s.questions.length) {
      final totalCorrect = s.answers.where((a) => a).length;
      final today = _todayString();

      // quiz_stats キャッシュを更新
      await _db.updateQuizStats(
        sessionCorrect: totalCorrect,
        sessionTotal: s.questions.length,
        quizDate: today,
      );

      final cachedStats = await _db.getCachedQuizStats();

      final prefs = await SharedPreferences.getInstance();

      state = QuizSummary(
        s.questions,
        s.answers,
        totalCorrect,
        cachedStats ?? {},
        s.selectedIndices,
      );

      // 完了フラグと回答結果を保存（次回配信まで表示し続ける）
      await prefs.setBool(_quizCompletedKey, true);
      await prefs.setString(_quizAnswersKey, jsonEncode(s.answers));
      await prefs.setString(_quizSelectedIndicesKey, jsonEncode(s.selectedIndices));
    } else {
      state = QuizAnswering(s.questions, nextIndex, s.answers, s.selectedIndices);
    }
  }

  /// 同じ問題でやり直し
  void retryQuiz() {
    if (state is! QuizSummary) return;
    final questions = (state as QuizSummary).questions;
    state = QuizAnswering(questions, 0, []);
  }

  String _todayString() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }
}

// ==================== Providers ====================

final quizControllerProvider =
    StateNotifierProvider<QuizController, QuizState>((ref) {
  return QuizController();
});

final quizStatsProvider = FutureProvider<QuizStatsData>((ref) async {
  final row = await DatabaseHelper.instance.getCachedQuizStats();
  return QuizStatsData.fromDatabase(row);
});
