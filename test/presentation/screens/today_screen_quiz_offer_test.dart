import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thai_memo/l10n/app_localizations.dart';
import 'package:thai_memo/core/config/app_config.dart';
import 'package:thai_memo/data/models/thai_sentence.dart';
import 'package:thai_memo/data/sentence_repository.dart';
import 'package:thai_memo/domain/delete_sentence_usecase.dart';
import 'package:thai_memo/domain/generate_sentence_usecase.dart';
import 'package:thai_memo/domain/get_sentences_usecase.dart';
import 'package:thai_memo/presentation/providers/analytics_provider.dart';
import 'package:thai_memo/presentation/providers/auth_provider.dart';
import 'package:thai_memo/presentation/providers/quiz_offer_experiment_provider.dart';
import 'package:thai_memo/presentation/providers/remaining_quota_provider.dart';
import 'package:thai_memo/presentation/providers/sentence_provider.dart';
import 'package:thai_memo/presentation/providers/settings_provider.dart';
import 'package:thai_memo/presentation/providers/subscription_provider.dart';
import 'package:thai_memo/presentation/providers/tts_provider.dart';
import 'package:thai_memo/presentation/providers/vocab_stats_provider.dart';
import 'package:thai_memo/presentation/screens/home_screen.dart';
import 'package:thai_memo/services/firebase_auth_service.dart';
import 'package:thai_memo/services/tts_service.dart';

import '../../helpers/fake_firebase.dart';

class _FakeSentenceRepository extends Fake implements SentenceRepository {}

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

ThaiSentence _sentence() => ThaiSentence(
      id: 'sentence-quiz-offer',
      thaiText: 'ฉันชอบภาษาไทย',
      pronunciation: 'chan chop phasa thai',
      japaneseTranslation: '私はタイ語が好きです',
      wordBreakdowns: const [],
      generationTier: 'free',
    );

SentenceController _sentenceController(FakeAnalyticsService analytics) {
  final repository = _FakeSentenceRepository();
  return SentenceController(
    GenerateSentenceUseCase(repository),
    GetSentencesUseCase(repository),
    DeleteSentenceUseCase(repository),
    analytics,
    () => 'free',
    () => null,
    () => false,
    () => lookupL10n(const Locale('ja')),
  )..showSentence(_sentence());
}

Future<void> _pumpTodayScreen(
  WidgetTester tester, {
  required QuizOfferVariant variant,
  required FakeAnalyticsService analytics,
  required SentenceController controller,
  LearningQuizStartCallback? onStartQuiz,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        analyticsServiceProvider.overrideWithValue(analytics),
        sentenceControllerProvider.overrideWith((ref) => controller),
        quizOfferVariantProvider.overrideWith((ref) async => variant),
        ttsServiceProvider.overrideWithValue(_FakeTtsService()),
        authControllerProvider.overrideWith(
          (ref) => AuthController(FirebaseAuthService.instance,
              () => lookupL10n(const Locale('ja'))),
        ),
        // 例文カード上の「次のテーマ」帯とヘッダーの語彙スコアが参照する。
        // 素で読むと planStatus 経由で Firebase を叩いてしまう。
        effectivePremiumProvider.overrideWithValue(false),
        // 帯が読むテーマ設定。settingsController は Firebase を要求する。
        generationParamsProvider.overrideWithValue(const {}),
        isPremiumProvider.overrideWithValue(false),
        isPremiumRealtimeProvider.overrideWithValue(const AsyncData(false)),
        premiumTrialExpiresAtProvider.overrideWithValue(const AsyncData(null)),
        vocabStatsProvider.overrideWith(
          (ref) => Stream.value(const VocabStats()),
        ),
      ],
      child: MaterialApp(
        locale: const Locale('ja'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: TodayScreen(onStartQuiz: onStartQuiz),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  late FakeFirebaseAuth auth;

  setUp(() {
    SharedPreferences.setMockInitialValues({
      // 初回ガイドは一巡済みとして測る。コーチマークが出ていると導線を
      // 覆ってしまい、実験の計測とは別の話になる。
      AppConfig.prefKeyTargetWordsCoachShown: true,
      AppConfig.prefKeyDetailCoachShown: true,
      AppConfig.prefKeySentenceCoachShown: true,
      AppConfig.prefKeyFirstSummaryQuizCompleted: false,
      AppConfig.prefKeyPremiumHintDismissedAt:
          DateTime.now().millisecondsSinceEpoch,
    });
    auth = FakeFirebaseAuth();
    FirebaseAuthService.authOverride = auth;
  });

  tearDown(() {
    FirebaseAuthService.authOverride = null;
  });

  testWidgets('control導線の表示とタップを同じsourceで一度だけ計測する', (tester) async {
    final analytics = FakeAnalyticsService();
    final controller = _sentenceController(analytics);
    ThaiSentence? tappedSentence;
    String? tappedSource;

    await _pumpTodayScreen(
      tester,
      variant: QuizOfferVariant.controlBottom,
      analytics: analytics,
      controller: controller,
      onStartQuiz: (sentence, source) {
        tappedSentence = sentence;
        tappedSource = source;
      },
    );

    expect(find.byKey(const ValueKey('quiz_offer_control_v1')), findsOneWidget);
    expect(
      analytics.quizOfferEvents,
      [
        {
          'action': 'assigned',
          'source': QuizOfferVariant.controlBottom.analyticsSource,
        },
        {
          'action': 'shown',
          'source': QuizOfferVariant.controlBottom.analyticsSource,
        },
      ],
    );

    // 同じ例文の再描画はimpressionとして重複計測しない。
    controller.showSentence(_sentence());
    await tester.pumpAndSettle();
    expect(analytics.quizOfferEvents, hasLength(2));

    await tester.tap(find.text('確認クイズへ'));
    await tester.pump();
    expect(tappedSentence?.id, 'sentence-quiz-offer');
    expect(tappedSource, QuizOfferVariant.controlBottom.analyticsSource);
    expect(
      analytics.quizOfferEvents.last,
      {
        'action': 'tapped',
        'source': QuizOfferVariant.controlBottom.analyticsSource,
      },
    );
  });

  testWidgets('inline導線は学習単語の直下に出た時点でshownを送る', (tester) async {
    tester.view.physicalSize = const Size(360, 320);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final analytics = FakeAnalyticsService();
    await _pumpTodayScreen(
      tester,
      variant: QuizOfferVariant.inlineOneQuestion,
      analytics: analytics,
      controller: _sentenceController(analytics),
    );

    expect(find.byKey(const ValueKey('quiz_offer_inline_v1')), findsOneWidget);

    // 学習単語の直下に常に描画するので、読み進めていなくても計測する。
    expect(
      analytics.quizOfferEvents,
      [
        {
          'action': 'assigned',
          'source': QuizOfferVariant.inlineOneQuestion.analyticsSource,
        },
        {
          'action': 'shown',
          'source': QuizOfferVariant.inlineOneQuestion.analyticsSource,
        },
      ],
    );
  });

  testWidgets('画面を作り直してもassignedは端末内で一度だけ送る', (tester) async {
    final analytics = FakeAnalyticsService();
    await _pumpTodayScreen(
      tester,
      variant: QuizOfferVariant.controlBottom,
      analytics: analytics,
      controller: _sentenceController(analytics),
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await _pumpTodayScreen(
      tester,
      variant: QuizOfferVariant.controlBottom,
      analytics: analytics,
      controller: _sentenceController(analytics),
    );

    expect(
      analytics.quizOfferEvents.where((event) => event['action'] == 'assigned'),
      hasLength(1),
    );
    expect(
      analytics.quizOfferEvents.where((event) => event['action'] == 'shown'),
      hasLength(2),
    );
  });

  testWidgets('割り当てを保存できない端末はcontrol表示だが実験計測から除外する', (tester) async {
    final analytics = FakeAnalyticsService();
    String? tappedSource = 'not-called';
    await _pumpTodayScreen(
      tester,
      variant: QuizOfferVariant.unassignedControl,
      analytics: analytics,
      controller: _sentenceController(analytics),
      onStartQuiz: (_, source) => tappedSource = source,
    );

    expect(find.text('確認クイズへ'), findsOneWidget);
    expect(analytics.quizOfferEvents, isEmpty);

    await tester.tap(find.text('確認クイズへ'));
    await tester.pump();
    expect(tappedSource, isNull);
    expect(analytics.quizOfferEvents, isEmpty);
  });
}
