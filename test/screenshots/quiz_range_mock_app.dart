// =============================================================================
// quiz_range_mock_app.dart
// セットの最後の確認クイズに正解した直後の結果画面（「まとめクイズへ」の手前）を、
// 本物の HomeScreen のタブ・LearningScreen の段・QuizScreen と同じ組み方で
// 差し込んだデータで載せてシミュレーターに出すモック。
// 「クイズの出題範囲を確認」を押すと復習タブへ切り替わり、「見ただけ＋覚えかけ」
// に絞った一覧で語彙スコアが真ん中に来る。
// Firebase なし。
//
//   flutter run -t test/screenshots/quiz_range_mock_app.dart
//   flutter run -t test/screenshots/quiz_range_mock_app.dart --dart-define=LANG=en
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:thai_memo/core/theme/app_theme.dart';
import 'package:thai_memo/data/models/quiz_question.dart';
import 'package:thai_memo/data/models/thai_sentence.dart';
import 'package:thai_memo/data/models/vocab_word.dart';
import 'package:thai_memo/l10n/app_localizations.dart';
import 'package:thai_memo/presentation/providers/analytics_provider.dart';
import 'package:thai_memo/presentation/providers/auth_provider.dart';
import 'package:thai_memo/presentation/providers/daily_set_provider.dart';
import 'package:thai_memo/presentation/providers/quiz_provider.dart';
import 'package:thai_memo/presentation/providers/remaining_quota_provider.dart';
import 'package:thai_memo/presentation/providers/settings_provider.dart';
import 'package:thai_memo/presentation/providers/tts_provider.dart';
import 'package:thai_memo/presentation/providers/vocab_progress_provider.dart';
import 'package:thai_memo/presentation/providers/vocab_stats_provider.dart';
import 'package:thai_memo/presentation/screens/quiz_screen.dart';
import 'package:thai_memo/presentation/screens/vocab_history_screen.dart';
import 'package:thai_memo/services/analytics_service.dart';
import 'package:thai_memo/services/daily_sentence_service.dart';
import 'package:thai_memo/services/tts_service.dart';

import 'store_mock_data.dart';

const _lang = String.fromEnvironment('LANG', defaultValue: 'ja');

/// store_mock_data の語彙一覧（スコア 642 の前後）に合わせる。
const _myVocab = 642;

void main() => runApp(const _MockApp());

class _MockApp extends StatelessWidget {
  const _MockApp();

  @override
  Widget build(BuildContext context) {
    final sentence = DailySentenceService.toSentence(
        'mock-sentence', storeSentenceJson(_lang));
    // 確認クイズは単語→意味の4択（meaning_choice）。
    final quiz = QuizQuestion.fromJson({
      ...storeQuizJson(_lang),
      'quiz_format': QuizQuestion.meaningChoiceFormat,
      'choices': switch (_lang) {
        'en' => ['beautiful', 'delicious', 'far', 'expensive'],
        'ko' => ['예쁘다', '맛있다', '멀다', '비싸다'],
        _ => ['きれい', 'おいしい', '遠い', '高い'],
      },
    });
    return ProviderScope(
      overrides: [
        analyticsServiceProvider.overrideWithValue(_NoopAnalytics()),
        ttsServiceProvider.overrideWithValue(_SilentTtsService()),
        authControllerProvider.overrideWith((ref) => _StubAuthController()),
        effectivePremiumProvider.overrideWithValue(true),
        planStatusProvider
            .overrideWithValue(const AsyncValue.data(PlanStatus.premium)),
        vocabStatsProvider.overrideWith(
          (ref) => Stream.value(const VocabStats(estimatedVocab: _myVocab)),
        ),
        vocabEntriesProvider
            .overrideWith((ref) async => storeVocabEntries(_lang)),
        // セットの最後の1本。
        dailySetProvider.overrideWith(
          (ref) => _StubDailySetController(
            DailySetState(
              setId: 'mock-set',
              sentences: List.filled(5, sentence),
              index: 4,
            ),
          ),
        ),
        // 確認クイズは答えるとすぐサマリーへ移る（QuizController の
        // _showSummary）。実機で「まとめクイズへ」が出るのはこの画面。
        quizControllerProvider.overrideWith(
          (ref) => _StubQuizController(
            QuizSummary([quiz], const [true], 1, const {}),
          ),
        ),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: const Locale(_lang),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        theme: buildAppLightTheme(ThaiFont.sarabun),
        home: _Home(sentence: sentence),
      ),
    );
  }
}

/// HomeScreen（下のタブ・IndexedStack）に LearningScreen の確認クイズの段と
/// 復習タブを載せたのと同じ組み方。タブの切り替えも HomeScreen._selectTab と同じ。
class _Home extends ConsumerStatefulWidget {
  const _Home({required this.sentence});

  final ThaiSentence sentence;

  @override
  ConsumerState<_Home> createState() => _HomeState();
}

class _HomeState extends ConsumerState<_Home> {
  int _index = 0;

  void _selectTab(int index, {Set<VocabMastery>? filters}) {
    if (index == 1 && _index != 1) {
      final req = ref.read(vocabTabRequestProvider.notifier);
      req.state = VocabTabRequest(req.state.seq + 1, filters: filters);
    }
    setState(() => _index = index);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          Scaffold(
            appBar: AppBar(
              title: Text(l10n.navLearn),
              automaticallyImplyLeading: false,
            ),
            body: QuizScreen(
              showAppBar: false,
              title: l10n.learnQuizTitle,
              learningSentence: widget.sentence,
              onBackToLearningStart: () {},
              nextButtonLabel: l10n.learnGoToSummaryQuiz,
              onNextSentence: () async {},
              onReviewRange: () => _selectTab(
                1,
                filters: const {VocabMastery.seen, VocabMastery.learning},
              ),
            ),
          ),
          const VocabHistoryScreen(),
          const Scaffold(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _selectTab,
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.school_outlined),
            selectedIcon: const Icon(Icons.school),
            label: l10n.navLearn,
          ),
          NavigationDestination(
            icon: const Icon(Icons.menu_book_outlined),
            selectedIcon: const Icon(Icons.menu_book),
            label: l10n.navHistory,
          ),
          NavigationDestination(
            icon: const Icon(Icons.settings_outlined),
            selectedIcon: const Icon(Icons.settings),
            label: l10n.navSettings,
          ),
        ],
      ),
    );
  }
}

class _StubAuthController extends StateNotifier<AuthState>
    implements AuthController {
  _StubAuthController() : super(const AuthState(isLinked: true));

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
