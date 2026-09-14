// 起動直後（まだ何も読み込んでいない状態）にサンプル例文を出さないことを押さえる。
//
// サンプルは「保存された例文が1本も無い」ことの表示であって、読み込み中の表示では
// ない。Initial をサンプルに落としていた頃は、起動処理が長引いたり落ちたりすると
// 「サンプルから画面が切り替わらない」ように見えていた。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thai_memo/l10n/app_localizations.dart';
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
import 'package:thai_memo/presentation/screens/today_screen.dart';
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

const _loadingText = '例文を準備中...';
const _sampleNotice = 'サンプル例文（履歴には保存されません）';
const _reloadLabel = '今日の例文を読み込む';

SentenceController _controller({
  required FakeAnalyticsService analytics,
  Future<ThaiSentence?> Function()? getMostRecent,
}) {
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
    getMostRecentSentence: getMostRecent ?? () async => null,
  );
}

Future<void> _pumpTodayScreen(
  WidgetTester tester, {
  required FakeAnalyticsService analytics,
  required SentenceController controller,
  Future<void> Function()? onReload,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        analyticsServiceProvider.overrideWithValue(analytics),
        sentenceControllerProvider.overrideWith((ref) => controller),
        quizOfferVariantProvider
            .overrideWith((ref) async => QuizOfferVariant.controlBottom),
        ttsServiceProvider.overrideWithValue(_FakeTtsService()),
        authControllerProvider.overrideWith(
          (ref) => AuthController(
            FirebaseAuthService.instance,
            () => lookupL10n(const Locale('ja')),
            clearLocalData: () async {},
          ),
        ),
        effectivePremiumProvider.overrideWithValue(false),
        generationParamsProvider.overrideWithValue(const {}),
        isPremiumProvider.overrideWithValue(false),
        premiumTrialExpiresAtProvider.overrideWithValue(const AsyncData(null)),
        vocabStatsProvider.overrideWith(
          (ref) => Stream.value(const VocabStats()),
        ),
      ],
      child: MaterialApp(
        locale: const Locale('ja'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: TodayScreen(onReload: onReload),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  late FakeFirebaseAuth auth;
  late FakeAnalyticsService analytics;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    auth = FakeFirebaseAuth();
    FirebaseAuthService.authOverride = auth;
    analytics = FakeAnalyticsService();
  });

  tearDown(() {
    FirebaseAuthService.authOverride = null;
  });

  testWidgets('読み込み前はサンプルではなくローディングを出す', (tester) async {
    await _pumpTodayScreen(
      tester,
      analytics: analytics,
      controller: _controller(analytics: analytics),
    );

    expect(find.text(_loadingText), findsOneWidget);
    expect(find.text(_sampleNotice), findsNothing);
  });

  testWidgets('読み込み中もサンプルを出さない', (tester) async {
    final controller = _controller(analytics: analytics)..markLoading();

    await _pumpTodayScreen(tester,
        analytics: analytics, controller: controller);

    expect(find.text(_loadingText), findsOneWidget);
    expect(find.text(_sampleNotice), findsNothing);
  });

  testWidgets('保存された例文が1本も無いと分かって初めてサンプルを出す', (tester) async {
    final controller = _controller(analytics: analytics);
    await _pumpTodayScreen(tester,
        analytics: analytics, controller: controller);

    await controller.loadMostRecent();
    await tester.pump();

    expect(controller.state, isA<SentenceStateEmpty>());
    expect(find.text(_sampleNotice), findsOneWidget);
    expect(find.text(_loadingText), findsNothing);
  });

  testWidgets('サンプル表示には取り直しの導線を出す', (tester) async {
    // 取り込みや生成が失敗してサンプルに落ちた人は、ここでしかやり直せない。
    var reloads = 0;
    final controller = _controller(analytics: analytics);
    await _pumpTodayScreen(
      tester,
      analytics: analytics,
      controller: controller,
      onReload: () async => reloads++,
    );

    await controller.loadMostRecent();
    await tester.pump();

    await tester.ensureVisible(find.text(_reloadLabel));
    await tester.tap(find.text(_reloadLabel));
    await tester.pump();

    expect(reloads, 1);
  });

  testWidgets('取り直しの手段が無ければボタンは出さない', (tester) async {
    final controller = _controller(analytics: analytics);
    await _pumpTodayScreen(
      tester,
      analytics: analytics,
      controller: controller,
    );

    await controller.loadMostRecent();
    await tester.pump();

    expect(find.text(_sampleNotice), findsOneWidget);
    expect(find.text(_reloadLabel), findsNothing);
  });
}
