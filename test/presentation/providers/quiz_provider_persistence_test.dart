import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thai_memo/data/datasources/backend_api_service.dart';
import 'package:thai_memo/data/datasources/local/database_helper.dart';
import 'package:thai_memo/data/models/quiz_question.dart';
import 'package:thai_memo/data/models/thai_sentence.dart';
import 'package:thai_memo/l10n/app_localizations.dart';
import 'package:thai_memo/presentation/providers/quiz_provider.dart';
import 'package:thai_memo/services/analytics_service.dart';

const _savedSummaryQuizKey = 'saved_summary_quiz';
const _savedConfirmationQuizKey = 'saved_confirmation_quiz';

QuizQuestion _question(int index) => QuizQuestion(
      sentenceId: 'sentence-$index',
      thaiText: 'ฉันชอบภาษาไทย',
      blankText: 'ฉันชอบ _____',
      correctAnswer: 'ภาษาไทย',
      choices: const ['ภาษาไทย', 'อาหาร', 'หนังสือ', 'เพลง'],
      pronunciation: 'phasa thai',
      explanation: 'タイ語',
    );

final _learningSentence = ThaiSentence(
  id: 'sentence-legacy',
  thaiText: 'ฉันชอบภาษาไทย',
  pronunciation: 'chan chop phasa thai',
  japaneseTranslation: '私はタイ語が好きです',
  wordBreakdowns: const [],
);

class _CountingBackendApiService extends Fake implements BackendApiService {
  _CountingBackendApiService({
    required this.summaryFallback,
    required this.learningFallback,
  });

  final List<QuizQuestion> summaryFallback;
  final List<QuizQuestion> learningFallback;
  int generateQuizCalls = 0;
  int generateLearningQuizCalls = 0;

  @override
  Future<List<QuizQuestion>> generateQuiz() async {
    generateQuizCalls++;
    return summaryFallback;
  }

  @override
  Future<List<QuizQuestion>> generateLearningQuiz(ThaiSentence sentence) async {
    generateLearningQuizCalls++;
    return learningFallback;
  }

  @override
  Future<void> updateUvm({
    required List<Map<String, dynamic>> results,
    String? quizType,
  }) async {}
}

class _FakeDatabaseHelper extends Fake implements DatabaseHelper {
  _FakeDatabaseHelper({this.cachedStats});

  final Map<String, dynamic>? cachedStats;

  @override
  Future<Map<String, dynamic>?> getCachedQuizStats() async => cachedStats;

  @override
  Future<int> insertQuizResult(Map<String, dynamic> result) async => 1;

  @override
  Future<void> updateQuizStats({
    required int sessionCorrect,
    required int sessionTotal,
    required String quizDate,
  }) async {}
}

class _FakeAnalyticsService extends Fake implements AnalyticsService {
  @override
  Future<void> logQuizStart({
    required String category,
    int? questionCount,
    String? source,
  }) async {}

  @override
  Future<void> logQuizAnswer({
    required bool correct,
    required String category,
    int? questionIndex,
    String? source,
  }) async {}
}

QuizController _controller({
  required _CountingBackendApiService backend,
  Map<String, dynamic>? cachedStats,
}) {
  return QuizController(
    backend,
    _FakeAnalyticsService(),
    () => lookupL10n(const Locale('ja')),
    databaseHelper: _FakeDatabaseHelper(cachedStats: cachedStats),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('旧result中間状態を次のQuizAnsweringへ復元しAPI生成しない', () async {
    final questions = [_question(1), _question(2), _question(3)];
    SharedPreferences.setMockInitialValues({
      _savedSummaryQuizKey: jsonEncode({
        'phase': 'result',
        'questions': questions.map((question) => question.toJson()).toList(),
        'index': 0,
        'answers': [true],
        // 旧スナップショットには以下のoptional履歴フィールドがない:
        // selected_indices / hint_levels / sentence_review_flags
      }),
    });
    final backend = _CountingBackendApiService(
      summaryFallback: [_question(99)],
      learningFallback: [_question(98)],
    );
    final controller = _controller(backend: backend);

    await controller.generateAndStartQuiz();

    expect(backend.generateQuizCalls, 0);
    expect(controller.state, isA<QuizAnswering>());
    final restored = controller.state as QuizAnswering;
    expect(restored.questions.map((question) => question.sentenceId),
        ['sentence-1', 'sentence-2', 'sentence-3']);
    expect(restored.index, 1);
    expect(restored.answers, [true]);
    expect(restored.selectedIndices, isEmpty);
    expect(restored.hintLevels, isEmpty);
    expect(restored.sentenceReviewFlags, isEmpty);
  });

  test('旧result最終状態をQuizSummaryへ復元しAPI生成しない', () async {
    final questions = [_question(1), _question(2), _question(3)];
    SharedPreferences.setMockInitialValues({
      _savedSummaryQuizKey: jsonEncode({
        'phase': 'result',
        'questions': questions.map((question) => question.toJson()).toList(),
        'index': 2,
        'answers': [true, false, true],
      }),
    });
    final backend = _CountingBackendApiService(
      summaryFallback: [_question(99)],
      learningFallback: [_question(98)],
    );
    final cachedStats = <String, dynamic>{
      'total_answered': 12,
      'total_correct': 9,
    };
    final controller = _controller(
      backend: backend,
      cachedStats: cachedStats,
    );

    await controller.generateAndStartQuiz();

    expect(backend.generateQuizCalls, 0);
    expect(controller.state, isA<QuizSummary>());
    final restored = controller.state as QuizSummary;
    expect(restored.answers, [true, false, true]);
    expect(restored.totalCorrect, 2);
    expect(restored.stats, cachedStats);
    expect(restored.selectedIndices, isEmpty);
    expect(restored.hintLevels, isEmpty);
    expect(restored.sentenceReviewFlags, isEmpty);
  });

  test('phaseなし旧confirmation状態をQuizAnsweringへ復元しAPI生成しない', () async {
    final savedQuestion = QuizQuestion(
      sentenceId: 'sentence-legacy',
      thaiText: 'ฉันชอบภาษาไทย',
      blankText: 'ฉันชอบ _____',
      correctAnswer: 'ภาษาไทย',
      choices: const ['ภาษาไทย', 'อาหาร', 'หนังสือ', 'เพลง'],
      pronunciation: 'phasa thai',
      explanation: 'タイ語',
    );
    SharedPreferences.setMockInitialValues({
      _savedConfirmationQuizKey: jsonEncode({
        'sentence_id': 'sentence-legacy',
        'questions': [savedQuestion.toJson()],
      }),
    });
    final backend = _CountingBackendApiService(
      summaryFallback: [_question(99)],
      learningFallback: [_question(98)],
    );
    final controller = _controller(backend: backend);

    await controller.startLearningQuiz(_learningSentence);

    expect(backend.generateLearningQuizCalls, 0);
    expect(controller.state, isA<QuizAnswering>());
    final restored = controller.state as QuizAnswering;
    expect(restored.index, 0);
    expect(restored.answers, isEmpty);
    expect(restored.questions.single.sentenceId, 'sentence-legacy');
  });

  test('新版の自動進行後も旧phaseとフィールド名で最新状態を保存する', () async {
    final questions = [_question(1), _question(2), _question(3)];
    final backend = _CountingBackendApiService(
      summaryFallback: questions,
      learningFallback: [_question(98)],
    );
    final controller = _controller(backend: backend);

    await controller.generateAndStartQuiz();
    await controller.answerQuestion(0);
    await controller.nextQuestion();

    // 保存キューの完了を待ち、result保存が次問題のanswering保存を
    // 後から上書きしないことも同時に確認する。
    expect(await controller.hasSavedSummaryQuiz(), isTrue);
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_savedSummaryQuizKey);
    expect(raw, isNotNull);
    final saved = jsonDecode(raw!) as Map<String, dynamic>;

    expect(saved['phase'], 'answering');
    expect(saved['index'], 1);
    expect(saved['answers'], [true]);
    expect(
        saved.keys,
        containsAll(<String>[
          'phase',
          'questions',
          'index',
          'answers',
          'selected_indices',
          'hint_levels',
          'sentence_review_flags',
        ]));
  });
}
