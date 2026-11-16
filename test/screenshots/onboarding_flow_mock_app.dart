// =============================================================================
// onboarding_flow_mock_app.dart
// 新しい初回導線（案）を、本物の画面にデータを差し込んでシミュレーターに出す
// モック。対象は「まったく初めて」（語彙テストなし・1セット2本）。
//
//   ヒアリング → 1本目（手順カード）→ 2本目 → まとめクイズの結果
//   → 「次のセットへ」でペイウォール（スコアが上がった／上がらなかったで一言を変える）
//
// 使い方ガイドの簡易版は出さない（手順カードが同じ役目を持つ）。
// Firebase なし。下の切り替えで場面を選ぶ。購入はしない。
//
//   flutter run -t test/screenshots/onboarding_flow_mock_app.dart
//   flutter run -t test/screenshots/onboarding_flow_mock_app.dart --dart-define=LANG=en
//   PHASE=3 でまとめクイズの結果から始める。
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thai_memo/core/theme/app_theme.dart';
import 'package:thai_memo/data/models/quiz_question.dart';
import 'package:thai_memo/l10n/app_localizations.dart';
import 'package:thai_memo/presentation/providers/analytics_provider.dart';
import 'package:thai_memo/presentation/providers/auth_provider.dart';
import 'package:thai_memo/presentation/providers/daily_set_provider.dart';
import 'package:thai_memo/presentation/providers/quiz_provider.dart';
import 'package:thai_memo/presentation/providers/remaining_quota_provider.dart';
import 'package:thai_memo/presentation/providers/sentence_provider.dart';
import 'package:thai_memo/presentation/providers/settings_provider.dart';
import 'package:thai_memo/presentation/providers/subscription_provider.dart';
import 'package:thai_memo/presentation/providers/tts_provider.dart';
import 'package:thai_memo/presentation/providers/vocab_stats_provider.dart';
import 'package:thai_memo/presentation/screens/interview_screen.dart';
import 'package:thai_memo/presentation/screens/paywall_screen.dart';
import 'package:thai_memo/presentation/screens/quiz_screen.dart';
import 'package:thai_memo/presentation/screens/today_screen.dart';
import 'package:thai_memo/presentation/widgets/first_set_steps.dart';
import 'package:thai_memo/services/analytics_service.dart';
import 'package:thai_memo/services/daily_sentence_service.dart';
import 'package:thai_memo/services/purchase_service.dart';
import 'package:thai_memo/services/tts_service.dart';

import 'store_mock_data.dart';

const _lang = String.fromEnvironment('LANG', defaultValue: 'ja');
const _initialPhase = int.fromEnvironment('PHASE');

/// まとめクイズで上がったときのスコア（0 → これ）。
const _scoreAfterUp = 6;

enum _Phase {
  interview('ヒアリング'),
  first('1本目'),
  second('2本目'),
  summaryUp('まとめ↑'),
  summaryFlat('まとめ→'),
  paywallUp('課金↑'),
  paywallFlat('課金→');

  const _Phase(this.label);
  final String label;

  bool get scoreUp => this == summaryUp || this == paywallUp;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 結果画面は「セット開始時のスコア」をここから読む（rememberVocabAtSetStart）。
  final prefs = await SharedPreferences.getInstance();
  await prefs.setInt('summary_quiz_vocab_before', 0);
  runApp(const _MockApp());
}

class _MockApp extends StatefulWidget {
  const _MockApp();

  @override
  State<_MockApp> createState() => _MockAppState();
}

class _MockAppState extends State<_MockApp> {
  _Phase _phase = _Phase.values[_initialPhase];
  final _sentence = DailySentenceService.toSentence(
      'mock-sentence', storeSentenceJson(_lang));
  final _second = DailySentenceService.toSentence(
      'mock-sentence-2', storeSentenceJson(_lang));
  late final _question = QuizQuestion.fromJson(storeQuizJson(_lang));

  void _go(_Phase phase) => setState(() => _phase = phase);

  @override
  Widget build(BuildContext context) {
    final up = _phase.scoreUp;
    return ProviderScope(
      key: ValueKey(_phase),
      overrides: [
        analyticsServiceProvider.overrideWithValue(_NoopAnalytics()),
        ttsServiceProvider.overrideWithValue(_SilentTtsService()),
        authControllerProvider.overrideWith((ref) => _StubAuthController()),
        effectivePremiumProvider.overrideWithValue(false),
        planStatusProvider
            .overrideWithValue(const AsyncValue.data(PlanStatus.free)),
        generationParamsProvider.overrideWithValue(const {}),
        userDocSnapshotProvider.overrideWith(
          (ref) => Stream.value(
              const UserDocSnapshot(data: null, isFromCache: false)),
        ),
        subscriptionControllerProvider
            .overrideWith((ref) => _StubSubscriptionController()),
        vocabStatsProvider.overrideWith(
          (ref) => Stream.value(
              VocabStats(estimatedVocab: up ? _scoreAfterUp : 0)),
        ),
        sentenceControllerProvider.overrideWith(
          (ref) => _StubSentenceController(SentenceStateSuccess(
              _phase == _Phase.second ? _second : _sentence)),
        ),
        // 入門者（まったく初めて）の初回セットは2本。
        dailySetProvider.overrideWith(
          (ref) => _StubDailySetController(
            DailySetState(
              setId: 'mock-set',
              sentences: [_sentence, _second],
              index: _phase == _Phase.first ? 0 : 1,
            ),
          ),
        ),
        firstSentenceIdProvider.overrideWith(
          (ref) => FirstSentenceIdController.fixed('mock-sentence'),
        ),
        firstStepsDoneProvider
            .overrideWith((ref) => FirstStepsDoneController.fixed(const {})),
        quizControllerProvider.overrideWith(
          (ref) => _StubQuizController(
            // 上がらなかった回は1問落としたことにする。
            QuizSummary(
              [_question, _question],
              up ? const [true, true] : const [true, false],
              up ? 2 : 1,
              const {},
            ),
          ),
        ),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: const Locale(_lang),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        theme: buildAppLightTheme(ThaiFont.sarabun),
        home: Scaffold(
          body: _body(),
          bottomNavigationBar: _PhaseBar(phase: _phase, onSelect: _go),
        ),
      ),
    );
  }

  Widget _body() {
    switch (_phase) {
      case _Phase.interview:
        return InterviewScreen(onComplete: () => _go(_Phase.first));
      case _Phase.first:
      case _Phase.second:
        return const SafeArea(bottom: false, child: TodayScreen());
      case _Phase.summaryUp:
      case _Phase.summaryFlat:
        // learning_screen.dart の LearningStage.summaryQuiz と同じ組み方。
        return Builder(builder: (context) {
          final l10n = L10n.of(context);
          return Scaffold(
            appBar: AppBar(
              title: Text(l10n.learnSummaryQuizTitle),
              automaticallyImplyLeading: false,
              actions: const [QuizProgressCounter()],
            ),
            body: QuizScreen(
              showAppBar: false,
              title: l10n.learnSummaryQuizTitle,
              showVocabScoreTransition: true,
              nextButtonLabel: l10n.learnNextSet,
              onNextSentence: () async => _go(_phase == _Phase.summaryUp
                  ? _Phase.paywallUp
                  : _Phase.paywallFlat),
            ),
          );
        });
      case _Phase.paywallUp:
      case _Phase.paywallFlat:
        return Builder(builder: (context) {
          final l10n = L10n.of(context);
          return PaywallScreen(
            source: 'mock',
            lead: _phase == _Phase.paywallUp
                ? l10n.paywallLeadScoreUp(_scoreAfterUp)
                : l10n.paywallLeadFirstSet,
          );
        });
    }
  }
}

/// モック用の場面切り替え。下のタブの位置に置く。
class _PhaseBar extends StatelessWidget {
  const _PhaseBar({required this.phase, required this.onSelect});

  final _Phase phase;
  final ValueChanged<_Phase> onSelect;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Row(
          children: [
            for (final p in _Phase.values)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text(p.label),
                  selected: p == phase,
                  onSelected: (_) => onSelect(p),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _StubSubscriptionController extends SubscriptionController {
  _StubSubscriptionController()
      : super(
          analytics: _NoopAnalytics(),
          l10n: () => lookupL10n(const Locale(_lang)),
        ) {
    final monthly = _product('premium_monthly', 'プレミアム（月額）', '¥600', 600);
    final yearly = _product('premium_annual', 'プレミアム（年額）', '¥4,800', 4800);
    state = SubscriptionState(
      product: monthly,
      yearlyProduct: yearly,
      lifetimeProduct:
          _product('premium_lifetime', 'プレミアム 買い切り', '¥5,800', 5800),
      // 新規の人はストアの無料トライアルが使える（「初回限定」が出る）。
      trials: {
        PremiumPlan.monthly: StoreTrial(product: monthly, days: 7),
        PremiumPlan.yearly: StoreTrial(product: yearly, days: 7),
      },
    );
  }

  static ProductDetails _product(
          String id, String title, String price, double rawPrice) =>
      ProductDetails(
        id: id,
        title: title,
        description: title,
        price: price,
        rawPrice: rawPrice,
        currencyCode: 'JPY',
      );
}

class _StubAuthController extends StateNotifier<AuthState>
    implements AuthController {
  _StubAuthController() : super(const AuthState(isLinked: true));

  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

class _StubSentenceController extends StateNotifier<SentenceState>
    implements SentenceController {
  _StubSentenceController(super.state);

  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

class _StubDailySetController extends StateNotifier<DailySetState>
    implements DailySetController {
  _StubDailySetController(super.state);

  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

class _StubQuizController extends StateNotifier<QuizState>
    implements QuizController {
  _StubQuizController(super.state);

  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

class _SilentTtsService extends Fake implements TtsService {
  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();

  @override
  void dispose() {}
}

class _NoopAnalytics extends Fake implements AnalyticsService {
  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

class Fake {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
