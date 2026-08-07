import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/widgets.dart';
import 'package:thai_memo/l10n/app_localizations.dart';
import 'package:thai_memo/data/datasources/backend_api_service.dart';
import 'package:thai_memo/data/datasources/local/database_helper.dart';
import 'package:thai_memo/data/models/quiz_question.dart';
import 'package:thai_memo/data/models/thai_sentence.dart';
import 'package:thai_memo/presentation/providers/quiz_provider.dart';

import '../../helpers/fake_firebase.dart';

const _question = QuizQuestion(
  sentenceId: 'sentence-1',
  thaiText: 'ฉันชอบภาษาไทย',
  blankText: 'ฉันชอบ _____',
  correctAnswer: 'ภาษาไทย',
  choices: ['ภาษาไทย', 'อาหาร', 'หนังสือ', 'เพลง'],
  pronunciation: 'phasa thai',
  explanation: 'タイ語',
);

final _sentence = ThaiSentence(
  id: 'sentence-1',
  thaiText: 'ฉันชอบภาษาไทย',
  pronunciation: 'chan chop phasa thai',
  japaneseTranslation: '私はタイ語が好きです',
  wordBreakdowns: const [],
);

class _FakeBackendApiService extends Fake implements BackendApiService {
  _FakeBackendApiService({
    this.learningQuestions = const [_question],
  });

  List<QuizQuestion> learningQuestions;

  @override
  Future<List<QuizQuestion>> generateLearningQuiz(ThaiSentence sentence) async {
    return learningQuestions;
  }

  @override
  Future<List<QuizQuestion>> generateQuiz() async => const [_question];

  @override
  Future<void> updateUvm({
    required List<Map<String, dynamic>> results,
    String? quizType,
  }) async {}
}

class _FakeDatabaseHelper extends Fake implements DatabaseHelper {
  @override
  Future<int> insertQuizResult(Map<String, dynamic> result) async => 1;

  @override
  Future<void> updateQuizStats({
    required int sessionCorrect,
    required int sessionTotal,
    required String quizDate,
  }) async {}

  @override
  Future<Map<String, dynamic>?> getCachedQuizStats() async => null;
}

void main() {
  late FakeAnalyticsService analytics;
  late QuizController controller;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    analytics = FakeAnalyticsService();
    controller = QuizController(
      _FakeBackendApiService(),
      analytics,
      () => lookupL10n(const Locale('ja')),
      databaseHelper: _FakeDatabaseHelper(),
    );
  });

  test('学習クイズはstartedと最初のansweredだけを導線source付きで送る', () async {
    const source = 'learning_quiz_control_v1';

    await controller.startLearningQuiz(_sentence, offerSource: source);
    expect(controller.state, isA<QuizAnswering>());
    expect(analytics.quizOfferEvents, [
      {'action': 'started', 'source': source},
    ]);
    expect(analytics.quizStartEvents.single, {
      'category': 'learning',
      'question_count': 1,
      'source': source,
    });

    await controller.answerQuestion(0);
    expect(controller.state, isA<QuizSummary>());
    expect(analytics.quizOfferEvents, [
      {'action': 'started', 'source': source},
      {'action': 'answered', 'source': source},
    ]);
    expect(analytics.quizAnswerEvents.single['category'], 'learning');

    controller.retryQuiz();
    await controller.answerQuestion(0);
    expect(
      analytics.quizOfferEvents.where((event) => event['action'] == 'started'),
      hasLength(1),
    );
    expect(
      analytics.quizOfferEvents.where((event) => event['action'] == 'answered'),
      hasLength(1),
    );
  });

  test('まとめクイズはquiz_offerイベントを送らない', () async {
    await controller.generateAndStartQuiz();
    await controller.answerQuestion(0);

    expect(analytics.quizOfferEvents, isEmpty);
    expect(analytics.quizStartEvents.single['category'], 'summary');
    expect(analytics.quizAnswerEvents.single['category'], 'summary');
  });

  test('事前生成して保存された未回答問題の復元でもstartedを送る', () async {
    SharedPreferences.setMockInitialValues({
      'saved_confirmation_quiz': jsonEncode({
        'phase': 'answering',
        'sentence_id': 'sentence-1',
        'questions': [_question.toJson()],
        'index': 0,
        'answers': <bool>[],
        'selected_indices': <int>[],
        'hint_levels': <int>[],
        'sentence_review_flags': <bool>[],
      }),
    });

    const source = 'learning_quiz_inline_v1';
    await controller.startLearningQuiz(_sentence, offerSource: source);

    expect(controller.state, isA<QuizAnswering>());
    expect(analytics.quizOfferEvents, [
      {'action': 'started', 'source': source},
    ]);
    expect(analytics.quizStartEvents.single['category'], 'learning');
  });

  test('生成error後の再試行でも同じsourceでstarted/answeredを送る', () async {
    final errorAnalytics = FakeAnalyticsService();
    final backend = _FakeBackendApiService(learningQuestions: const []);
    final errorController = QuizController(
      backend,
      errorAnalytics,
      () => lookupL10n(const Locale('ja')),
      databaseHelper: _FakeDatabaseHelper(),
    );
    const source = 'learning_quiz_inline_v1';

    await errorController.startLearningQuiz(_sentence, offerSource: source);

    expect(errorController.state, isA<QuizError>());
    expect(errorAnalytics.quizOfferEvents, [
      {'action': 'error', 'source': source},
    ]);

    backend.learningQuestions = const [_question];
    await errorController.retryLearningQuiz(_sentence);
    await errorController.answerQuestion(0);
    expect(errorAnalytics.quizOfferEvents, [
      {'action': 'error', 'source': source},
      {'action': 'started', 'source': source},
      {'action': 'answered', 'source': source},
    ]);
  });
}
