import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thai_memo/data/datasources/backend_api_service.dart';
import 'package:thai_memo/data/datasources/local/database_helper.dart';
import 'package:thai_memo/data/models/quiz_question.dart';
import 'package:thai_memo/l10n/app_localizations.dart';
import 'package:thai_memo/presentation/providers/quiz_provider.dart';
import 'package:thai_memo/services/analytics_service.dart';
import 'package:thai_memo/services/learning_progress_store.dart';

QuizQuestion _question(int index) => QuizQuestion(
      sentenceId: 'sentence-$index',
      thaiText: 'ฉันชอบภาษาไทย',
      blankText: 'ฉันชอบ _____',
      correctAnswer: 'ภาษาไทย',
      choices: const ['ภาษาไทย', 'อาหาร', 'หนังสือ', 'เพลง'],
      pronunciation: 'phasa thai',
      explanation: 'タイ語',
    );

class _Backend extends Fake implements BackendApiService {
  _Backend(this.questions);

  final List<QuizQuestion> questions;
  final uvmWords = <String>[];

  @override
  Future<List<QuizQuestion>> generateQuiz() async => questions;

  @override
  Future<void> updateUvm({
    required List<Map<String, dynamic>> results,
    String? quizType,
  }) async {
    uvmWords.addAll(results.map((r) => r['word'] as String));
  }
}

class _Db extends Fake implements DatabaseHelper {
  int inserted = 0;
  int? statsCorrect;
  int? statsTotal;

  @override
  Future<Map<String, dynamic>?> getCachedQuizStats() async => const {};

  @override
  Future<int> insertQuizResult(Map<String, dynamic> result) async =>
      ++inserted;

  @override
  Future<void> updateQuizStats({
    required int sessionCorrect,
    required int sessionTotal,
    required String quizDate,
  }) async {
    statsCorrect = sessionCorrect;
    statsTotal = sessionTotal;
  }
}

class _Analytics extends Fake implements AnalyticsService {
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
    String? quizFormat,
    int? srsInterval,
    int? responseMs,
  }) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('5問に満たないまとめクイズはコツ問題を1問足し、スコアには入れない', () async {
    final backend = _Backend([_question(1), _question(2)]);
    final db = _Db();
    var cloudPushes = 0;
    final controller = QuizController(
      backend,
      _Analytics(),
      () => lookupL10n(const Locale('ja')),
      databaseHelper: db,
      progressStore: LearningProgressStore(),
      onSummaryQuizSaved: (_) => cloudPushes++,
    );

    await controller.generateAndStartQuiz();
    final start = controller.state as QuizAnswering;
    expect(start.questions.length, 3);
    expect(start.questions.last.isTip, isTrue);

    // 例文2問は正解、コツ問題は全部はずす。
    for (var i = 0; i < 3; i++) {
      final q = (controller.state as QuizAnswering).questions[i];
      final pick = q.isTip
          ? q.choices.indexWhere((c) => c != q.correctChoice)
          : q.choices.indexOf(q.correctChoice);
      await controller.answerQuestion(pick);
      await controller.nextQuestion();
    }

    final summary = controller.state as QuizSummary;
    expect(summary.answers, [true, true, false]);
    expect(db.inserted, 2);
    expect(backend.uvmWords, ['ภาษาไทย', 'ภาษาไทย']);
    expect(db.statsCorrect, 2);
    expect(db.statsTotal, 2);

    await controller.waitForSavedQuizWrites();
    expect(cloudPushes, 0);

    // 途中経過は端末には残り、復元できる。
    final restored = QuizController(
      backend,
      _Analytics(),
      () => lookupL10n(const Locale('ja')),
      databaseHelper: db,
      progressStore: LearningProgressStore(),
    );
    expect(await restored.restoreSavedSummaryQuiz(), isTrue);
    expect(restored.state, isA<QuizSummary>());
  });

  test('5問そろっていれば足さない', () async {
    final controller = QuizController(
      _Backend(List.generate(5, _question)),
      _Analytics(),
      () => lookupL10n(const Locale('ja')),
      databaseHelper: _Db(),
      progressStore: LearningProgressStore(),
    );
    await controller.generateAndStartQuiz();
    final state = controller.state as QuizAnswering;
    expect(state.questions.length, 5);
    expect(state.questions.any((q) => q.isTip), isFalse);
  });
}
