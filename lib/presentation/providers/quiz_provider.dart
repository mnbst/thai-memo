import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/datasources/backend_api_service.dart'
    show BackendApiRateLimitException, BackendApiService;
import '../../data/datasources/local/database_helper.dart';
import '../../data/models/quiz_question.dart';
import '../../data/models/quiz_result.dart';
import '../../services/analytics_service.dart';
import 'analytics_provider.dart';

final RegExp _thaiScriptRegex = RegExp(r'[\u0E00-\u0E7F]');
final RegExp _nonThaiChoiceRegex =
    RegExp(r'[A-Za-z\u3040-\u30FF\u31F0-\u31FF\u4E00-\u9FFF]');

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

/// 復習対象があることを表示する状態
class QuizPending extends QuizState {
  final int questionCount;
  const QuizPending(this.questionCount);
}

/// クイズ生成中（Gemini API呼び出し中）
class QuizGenerating extends QuizState {
  const QuizGenerating();
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
  final List<int>? hintLevels;

  const QuizAnswering(
    this.questions,
    this.index,
    this.answers, [
    this.selectedIndices = const [],
    this.hintLevels = const [],
  ]);
}

class QuizShowResult extends QuizState {
  final List<QuizQuestion> questions;
  final int index;
  final List<bool> answers;
  final int selectedIndex;
  final bool isCorrect;
  final List<int> selectedIndices;
  final List<int>? hintLevels;

  const QuizShowResult(
    this.questions,
    this.index,
    this.answers,
    this.selectedIndex,
    this.isCorrect, [
    this.selectedIndices = const [],
    this.hintLevels = const [],
  ]);
}

class QuizSummary extends QuizState {
  final List<QuizQuestion> questions;
  final List<bool> answers;
  final int totalCorrect;
  final Map<String, dynamic> stats;
  final List<int> selectedIndices;
  final List<int>? hintLevels;

  const QuizSummary(
    this.questions,
    this.answers,
    this.totalCorrect,
    this.stats, [
    this.selectedIndices = const [],
    this.hintLevels = const [],
  ]);
}

/// クイズ生成エラー
class QuizError extends QuizState {
  final String message;
  const QuizError(this.message);
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
  final BackendApiService _apiService;
  final AnalyticsService _analytics;

  QuizController(this._apiService, this._analytics)
      : super(const QuizInitial());

  /// クイズデータを読み込み（SharedPreferencesから復元 or Pending表示）
  Future<void> loadQuiz() async {
    // クイズ進行中・結果表示中はリロードしない
    if (state is QuizAnswering ||
        state is QuizShowResult ||
        state is QuizGenerating ||
        state is QuizSummary) {
      return;
    }
    state = const QuizLoading();

    try {
      final prefs = await SharedPreferences.getInstance();
      final existingJson = prefs.getString(_quizKey);

      // 端末にデータがあればそれを使用
      if (existingJson != null && existingJson.isNotEmpty) {
        await _loadFromPrefs();
        return;
      }

      // 端末にデータがない → Pending表示（SRS選出はgenerateQuiz時にリアルタイム実行）
      state = const QuizPending(0);
    } catch (e) {
      debugPrint('クイズ読み込みエラー: $e');
      state = const QuizPending(0);
    }
  }

  /// クイズをオンデマンド生成して開始準備
  Future<void> generateAndStartQuiz() async {
    state = const QuizGenerating();

    try {
      final questions = await _apiService.generateQuiz();
      if (questions.isEmpty || _hasInvalidQuizChoices(questions)) {
        state = const QuizError('クイズの生成に失敗しました。もう一度お試しください。');
        return;
      }

      // SharedPreferencesに保存
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _quizKey,
        jsonEncode(questions.map((q) => q.toJson()).toList()),
      );
      await prefs.remove(_quizCompletedKey);
      await prefs.remove(_quizAnswersKey);
      await prefs.remove(_quizSelectedIndicesKey);

      state = QuizReady(questions);
    } on BackendApiRateLimitException {
      state = const QuizError('本日のクイズ生成上限に達しました。');
    } catch (e) {
      debugPrint('クイズ生成エラー: $e');
      state = const QuizError('クイズの生成に失敗しました。もう一度お試しください。');
    }
  }

  /// SharedPreferencesから既存クイズを復元
  Future<void> _loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_quizKey);

    if (json == null || json.isEmpty) {
      state = const QuizPending(0);
      return;
    }

    try {
      final list = jsonDecode(json) as List<dynamic>;
      final questions = list
          .map((e) => QuizQuestion.fromJson(e as Map<String, dynamic>))
          .toList();
      if (questions.isEmpty) {
        state = const QuizPending(0);
        return;
      }
      if (_hasInvalidQuizChoices(questions)) {
        await _clearStoredQuiz();
        state = const QuizPending(0);
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
        state = QuizSummary(
          questions,
          answers,
          totalCorrect,
          cachedStats ?? {},
          selectedIndices,
        );
        return;
      }

      state = QuizReady(questions);
    } catch (_) {
      await _clearStoredQuiz();
      state = const QuizPending(0);
    }
  }

  bool _hasInvalidQuizChoices(List<QuizQuestion> questions) {
    return questions.any((question) {
      if (question.choices.length != 4) {
        return true;
      }
      if (!_isThaiChoice(question.correctAnswer)) {
        return true;
      }
      if (!question.choices.contains(question.correctAnswer)) {
        return true;
      }
      return question.choices.any((choice) => !_isThaiChoice(choice));
    });
  }

  bool _isThaiChoice(String text) {
    final normalized = text.trim();
    return normalized.isNotEmpty &&
        _thaiScriptRegex.hasMatch(normalized) &&
        !_nonThaiChoiceRegex.hasMatch(normalized);
  }

  Future<void> _clearStoredQuiz() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_quizKey);
    await prefs.remove(_quizCompletedKey);
    await prefs.remove(_quizAnswersKey);
    await prefs.remove(_quizSelectedIndicesKey);
  }

  /// クイズ開始
  void startQuiz() {
    if (state is! QuizReady) return;
    final questions = (state as QuizReady).questions;
    state = QuizAnswering(questions, 0, []);
    // 実際に回答フローへ入ったタイミングだけを quiz_start として記録する。
    unawaited(
      _analytics.logQuizStart(
        category: 'sentence_review',
        questionCount: questions.length,
      ),
    );
  }

  /// 回答を選択
  Future<void> answerQuestion(int choiceIndex, {int hintLevel = 0}) async {
    if (state is! QuizAnswering) return;
    final s = state as QuizAnswering;
    final question = s.questions[s.index];
    final isCorrect = question.choices[choiceIndex] == question.correctAnswer;
    final newAnswers = [...s.answers, isCorrect];
    final newSelectedIndices = [...s.selectedIndices, choiceIndex];
    final newHintLevels = <int>[...s.hintLevels ?? const [], hintLevel];

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

    // UVM更新: 1問ごとにfire-and-forgetで送信
    final word = question.correctAnswer;
    if (word.isNotEmpty) {
      _apiService.updateUvm(results: [
        {'word': word, 'is_correct': isCorrect, 'hint_level': hintLevel},
      ]);
    }

    state = QuizShowResult(
      s.questions,
      s.index,
      newAnswers,
      choiceIndex,
      isCorrect,
      newSelectedIndices,
      newHintLevels,
    );
    // DB 保存と同じタイミングで送ることで、集計と UI の見え方を揃える。
    unawaited(
      _analytics.logQuizAnswer(
        correct: isCorrect,
        category: 'sentence_review',
        questionIndex: s.index + 1,
      ),
    );
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
        s.hintLevels,
      );

      // 完了フラグと回答結果を保存（次回配信まで表示し続ける）
      await prefs.setBool(_quizCompletedKey, true);
      await prefs.setString(_quizAnswersKey, jsonEncode(s.answers));
      await prefs.setString(
          _quizSelectedIndicesKey, jsonEncode(s.selectedIndices));
    } else {
      state = QuizAnswering(
          s.questions, nextIndex, s.answers, s.selectedIndices, s.hintLevels ?? const []);
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
  return QuizController(
    BackendApiService(),
    ref.watch(analyticsServiceProvider),
  );
});

final quizStatsProvider = FutureProvider<QuizStatsData>((ref) async {
  final row = await DatabaseHelper.instance.getCachedQuizStats();
  return QuizStatsData.fromDatabase(row);
});
