// 学習タブの段（例文 → 確認クイズ → まとめクイズ）が、再起動をまたいで
// どこまで戻るかを押さえる。
//
// 起動時の順序を実機に合わせている: LearningScreen が先に立ち上がり、
// HomeScreen が走らせるカーソル復元（dailySetProvider.restore）はその後に
// 終わる。段の決定がこの順序に引きずられないことを確かめる。
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thai_memo/data/datasources/backend_api_service.dart';
import 'package:thai_memo/data/datasources/local/database_helper.dart';
import 'package:thai_memo/data/models/quiz_question.dart';
import 'package:thai_memo/data/models/thai_sentence.dart';
import 'package:thai_memo/data/sentence_repository.dart';
import 'package:thai_memo/domain/delete_sentence_usecase.dart';
import 'package:thai_memo/domain/generate_sentence_usecase.dart';
import 'package:thai_memo/domain/get_sentences_usecase.dart';
import 'package:thai_memo/l10n/app_localizations.dart';
import 'package:thai_memo/presentation/providers/analytics_provider.dart';
import 'package:thai_memo/presentation/providers/auth_provider.dart';
import 'package:thai_memo/presentation/providers/daily_set_provider.dart';
import 'package:thai_memo/presentation/providers/quiz_offer_experiment_provider.dart';
import 'package:thai_memo/presentation/providers/quiz_provider.dart';
import 'package:thai_memo/presentation/providers/remaining_quota_provider.dart';
import 'package:thai_memo/presentation/providers/sentence_provider.dart';
import 'package:thai_memo/presentation/providers/settings_provider.dart';
import 'package:thai_memo/presentation/providers/subscription_provider.dart';
import 'package:thai_memo/presentation/providers/tts_provider.dart';
import 'package:thai_memo/presentation/providers/vocab_stats_provider.dart';
import 'package:thai_memo/presentation/screens/learning_screen.dart';
import 'package:thai_memo/services/analytics_service.dart';
import 'package:thai_memo/services/daily_set_progress_store.dart';
import 'package:thai_memo/services/firebase_auth_service.dart';
import 'package:thai_memo/services/learning_progress_store.dart';
import 'package:thai_memo/services/tts_service.dart';

import '../../helpers/fake_firebase.dart';

const _savedSummaryQuizKey = 'saved_summary_quiz';
const _progressKey = 'daily_set_progress';

ThaiSentence _sentence(String id) => ThaiSentence(
      id: id,
      thaiText: 'ฉันชอบภาษาไทย',
      pronunciation: 'chan chop phasa thai',
      japaneseTranslation: '私はタイ語が好きです',
      wordBreakdowns: const [],
      generationTier: 'free',
    );

QuizQuestion _question(int index) => QuizQuestion(
      sentenceId: 'sentence-$index',
      thaiText: 'ฉันชอบภาษาไทย',
      blankText: 'ฉันชอบ _____',
      correctAnswer: 'ภาษาไทย',
      choices: const ['ภาษาไทย', 'อาหาร', 'หนังสือ', 'เพลง'],
      pronunciation: 'phasa thai',
      explanation: 'タイ語',
    );

class _FakeBackendApiService extends Fake implements BackendApiService {
  int generateQuizCalls = 0;

  @override
  Future<List<QuizQuestion>> generateQuiz() async {
    generateQuizCalls++;
    return [_question(99)];
  }

  @override
  Future<void> updateUvm({
    required List<Map<String, dynamic>> results,
    String? quizType,
  }) async {}
}

class _FakeDatabaseHelper extends Fake implements DatabaseHelper {
  @override
  Future<Map<String, dynamic>?> getCachedQuizStats() async => null;

  @override
  Future<int> insertQuizResult(Map<String, dynamic> result) async => 1;

  @override
  Future<void> updateQuizStats({
    required int sessionCorrect,
    required int sessionTotal,
    required String quizDate,
  }) async {}
}

class _FakeQuizAnalytics extends Fake implements AnalyticsService {
  @override
  Future<void> logQuizStart({
    required String category,
    int? questionCount,
    String? source,
  }) async {}
}

class _FakeSentenceRepository extends Fake implements SentenceRepository {
  _FakeSentenceRepository(this.byId);

  final Map<String, ThaiSentence> byId;

  @override
  Future<ThaiSentence?> getSentenceById(String id) async => byId[id];
}

class _NoopProgressStore implements DailySetProgressStore {
  @override
  Future<ThaiSentence?> fetchSentence(String id) async => null;

  @override
  Future<DailySetProgressSnapshot?> merge(
    DailySetProgressSnapshot local,
  ) async =>
      null;
}

class _FakeTtsService extends Fake implements TtsService {
  @override
  int get session => 0;

  @override
  void Function(int start, int end)? onProgress;

  @override
  Future<void> stop({bool waitForCancel = false}) async {}

  @override
  Future<void> stopAll() async {}

  @override
  Future<void> speak(
    String text, {
    bool slow = false,
    bool keepVoice = false,
  }) async {}
}

SentenceController _sentenceController(FakeAnalyticsService analytics) {
  final repository = _FakeSentenceRepository(const {});
  return SentenceController(
    GenerateSentenceUseCase(repository),
    GetSentencesUseCase(repository),
    DeleteSentenceUseCase(repository),
    analytics,
    () => 'free',
    () => null,
    () => false,
    () => lookupL10n(const Locale('ja')),
  );
}

/// まとめクイズの結果画面まで進めて閉じた端末の保存内容。
void _seedFinishedSummaryQuiz({required String setId}) {
  final ids = ['a', 'b', 'c', 'd', 'e'];
  SharedPreferences.setMockInitialValues({
    _progressKey: jsonEncode({
      'active': {'set_id': setId, 'sentence_ids': ids},
      'active_index': ids.length - 1,
      'active_sentence_id': ids.last,
      'pending': <dynamic>[],
      'completed_set_ids': <String>[],
    }),
    _savedSummaryQuizKey: jsonEncode({
      'phase': 'summary',
      'set_id': setId,
      'questions': [_question(1).toJson()],
      'answers': [true],
      'total_correct': 1,
      'stats': <String, dynamic>{},
    }),
  });
}

Future<ProviderContainer> _pumpLearningScreen(
  WidgetTester tester, {
  required _FakeBackendApiService backend,
}) async {
  final analytics = FakeAnalyticsService();
  final byId = {
    for (final id in ['a', 'b', 'c', 'd', 'e']) id: _sentence(id)
  };
  final container = ProviderContainer(
    overrides: [
      sentenceRepositoryProvider
          .overrideWithValue(_FakeSentenceRepository(byId)),
      dailySetProgressStoreProvider.overrideWithValue(_NoopProgressStore()),
      quizControllerProvider.overrideWith(
        (ref) => QuizController(
          backend,
          _FakeQuizAnalytics(),
          () => lookupL10n(const Locale('ja')),
          databaseHelper: _FakeDatabaseHelper(),
        ),
      ),
      sentenceControllerProvider
          .overrideWith((ref) => _sentenceController(analytics)),
      analyticsServiceProvider.overrideWithValue(analytics),
      quizOfferVariantProvider
          .overrideWith((ref) async => QuizOfferVariant.controlBottom),
      ttsServiceProvider.overrideWithValue(_FakeTtsService()),
      authControllerProvider.overrideWith(
        (ref) => AuthController(
          FirebaseAuthService.instance,
          () => lookupL10n(const Locale('ja')),
        ),
      ),
      effectivePremiumProvider.overrideWithValue(false),
      generationParamsProvider.overrideWithValue(const {}),
      isPremiumProvider.overrideWithValue(false),
      isPremiumRealtimeProvider.overrideWithValue(const AsyncData(false)),
      premiumTrialExpiresAtProvider.overrideWithValue(const AsyncData(null)),
      vocabStatsProvider.overrideWith(
        (ref) => Stream.value(const VocabStats(estimatedVocab: 20)),
      ),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: const Locale('ja'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: const LearningScreen(),
      ),
    ),
  );
  // LearningScreen の postFrame（段の決定）がここで走る。
  await tester.pump();
  return container;
}

/// いまの保存形（1レコード）で、まとめクイズの結果まで進めて閉じた端末。
void _seedFinishedSummaryQuizRecord({required String setId}) {
  final ids = ['a', 'b', 'c', 'd', 'e'];
  SharedPreferences.setMockInitialValues({
    LearningProgressStore.key: jsonEncode(
      LearningProgressRecord(
        set: DailySetProgressSnapshot(
          active: DailySetRef(setId: setId, sentenceIds: ids),
          activeSentenceId: ids.last,
        ),
        stage: LearningStage.summaryQuiz,
        summaryQuiz: {
          'phase': 'summary',
          'questions': [_question(1).toJson()],
          'answers': [true],
          'total_correct': 1,
          'stats': <String, dynamic>{},
        },
      ).toJson(),
    ),
  });
}

void main() {
  late FakeFirebaseAuth auth;

  setUp(() {
    auth = FakeFirebaseAuth();
    FirebaseAuthService.authOverride = auth;
  });

  tearDown(() {
    FirebaseAuthService.authOverride = null;
  });

  testWidgets('まとめクイズの結果で閉じたら、再起動しても結果画面に戻る', (tester) async {
    // 結果画面で離脱して再起動すると、クイズ直前の例文へ戻ってまとめクイズを
    // やり直しになる、という報告の回帰テスト。
    _seedFinishedSummaryQuiz(setId: 'set-a');
    final backend = _FakeBackendApiService();

    final container = await _pumpLearningScreen(tester, backend: backend);

    // HomeScreen 側のカーソル復元は、段の決定より後に終わる。
    await container.read(dailySetProvider.notifier).restore();
    await tester.pump(const Duration(milliseconds: 100));

    expect(container.read(dailySetProvider).setId, 'set-a');
    expect(find.text('まとめクイズ'), findsWidgets);
    expect(backend.generateQuizCalls, 0);
  });

  testWidgets('いまの保存形でも、結果画面のまま再起動できる', (tester) async {
    _seedFinishedSummaryQuizRecord(setId: 'set-a');
    final backend = _FakeBackendApiService();

    final container = await _pumpLearningScreen(tester, backend: backend);
    await container.read(dailySetProvider.notifier).restore();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('まとめクイズ'), findsWidgets);
    expect(container.read(quizControllerProvider), isA<QuizSummary>());
    expect(backend.generateQuizCalls, 0);
  });

  testWidgets('次のセットへ移ると、段もクイズの保存も残さない', (tester) async {
    // 捨てる場所を1か所（カーソルの保存）に寄せた分の確認。持ち主を突き合わせ
    // なくても、終わったセットのまとめクイズが次の起動で開かない。
    _seedFinishedSummaryQuizRecord(setId: 'set-a');
    final container = await _pumpLearningScreen(
      tester,
      backend: _FakeBackendApiService(),
    );
    await container.read(dailySetProvider.notifier).restore();
    await tester.pump(const Duration(milliseconds: 100));

    await container.read(dailySetProvider.notifier).start(
      [for (final id in ['f', 'g']) _sentence(id)],
      setId: 'set-b',
    );
    await tester.pump(const Duration(milliseconds: 100));

    final record = await LearningProgressStore().load();
    expect(record.set.active?.setId, 'set-b');
    expect(record.stage, LearningStage.sentence);
    expect(record.summaryQuiz, isNull);
    expect(record.confirmationQuiz, isNull);
  });

  testWidgets('カーソル復元が終わるまで段を決めない', (tester) async {
    // 復元前に段を決めると、持ち主（セットID）が未確定のまま照合され、
    // 保存されたまとめクイズが必ず捨てられる。
    _seedFinishedSummaryQuiz(setId: 'set-a');
    final backend = _FakeBackendApiService();

    final container = await _pumpLearningScreen(tester, backend: backend);

    // カーソル復元より前の時点では、まだ例文画面を出していてよい。
    // ただし、この時点で「保存を捨てた」状態になっていてはいけない。
    await container.read(dailySetProvider.notifier).restore();
    await tester.pump(const Duration(milliseconds: 100));

    expect(container.read(quizControllerProvider), isA<QuizSummary>());
  });
}
