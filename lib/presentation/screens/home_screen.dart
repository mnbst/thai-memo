import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/config/app_config.dart';
import '../../data/models/syllable.dart';
import '../../data/models/thai_sentence.dart';
import '../../data/models/word_breakdown.dart';
import '../providers/analytics_provider.dart';
import '../providers/sentence_provider.dart';
import '../providers/quiz_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/tts_provider.dart';
import '../providers/remaining_quota_provider.dart';
import '../providers/subscription_provider.dart';
import '../providers/vocab_stats_provider.dart';
import '../widgets/loading_tip_carousel.dart';
import '../widgets/vocab_score_dialog.dart';
import 'detail_screen.dart';
import 'paywall_screen.dart';
import 'history_screen.dart';
import 'onboarding_screen.dart';
import 'quiz_screen.dart';
import 'settings_screen.dart';

/// Home screen with bottom navigation
class HomeScreen extends ConsumerStatefulWidget {
  static const routeName = 'home';

  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with WidgetsBindingObserver {
  int _currentIndex = 0;
  bool _initialLoadCompleted = false;
  final _showAppIcon = ValueNotifier<bool>(true);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _logCurrentTabScreen();
      _checkFirstLaunchAndLoadSentence();
      // remaining_sentences監視: 0→正数（dailyBatchリセット）で自動読み込み
      ref.listenManual(remainingSentencesProvider, (prev, next) {
        if (!_initialLoadCompleted) return;
        if (_changedFromNoRemainingToAvailable(prev, next)) {
          // dailyBatchリセット時は表示中でも新日の例文を生成
          ref.read(sentenceControllerProvider.notifier).loadOrGenerateToday(
                dailySentenceGenerated: false,
              );
          ref.invalidate(allSentencesProvider);
        }
      });
    });
  }

  @override
  void dispose() {
    _showAppIcon.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkAndReloadIfNeeded();
    }
  }

  /// アプリ復帰時にFirestoreフラグを確認し、未生成なら再ロード
  Future<void> _checkAndReloadIfNeeded() async {
    // 初回ロードが完了する前はスキップ（_checkFirstLaunchAndLoadSentenceとの二重生成を防ぐ）
    if (!_initialLoadCompleted) return;

    // 生成中ならスキップ
    final currentState = ref.read(sentenceControllerProvider);
    if (currentState is SentenceStateLoading) {
      return;
    }

    final data = await ref.read(userDocProvider.future);
    final isGenerated = (data?['daily_sentence_generated'] as bool?) ?? false;

    // 今日の生成済みフラグが立っていて表示成功状態なら、そのまま維持する
    if (isGenerated && currentState is SentenceStateSuccess) {
      return;
    }

    if (!isGenerated) {
      ref.read(sentenceControllerProvider.notifier).loadOrGenerateToday(
            dailySentenceGenerated: false,
          );
      ref.invalidate(allSentencesProvider);
    }
  }

  /// Check if first launch and load sentence
  Future<void> _checkFirstLaunchAndLoadSentence() async {
    // 設定の読み込み完了を待ってから判定する
    await ref.read(settingsControllerProvider.notifier).initialized;
    final isFirstLaunch = ref.read(isFirstLaunchProvider);

    if (isFirstLaunch) {
      if (mounted) {
        // オンボーディング画面を表示し、完了を待つ
        await Navigator.push<void>(
          context,
          MaterialPageRoute(
            settings: const RouteSettings(name: OnboardingScreen.routeName),
            builder: (context) => OnboardingScreen(
              onComplete: () {
                Navigator.pop(context);
              },
            ),
          ),
        );
      }
      // 初回起動完了を記録
      ref.read(settingsControllerProvider.notifier).completeFirstLaunch();

      if (mounted) {
        _showFirstTimeGuideDialog();
      }
    }

    if (!mounted) return;

    // Firestoreフラグを取得し、未生成なら自動生成、済みなら最新を表示
    final data2 = await ref.read(userDocProvider.future);
    final isGenerated = (data2?['daily_sentence_generated'] as bool?) ?? false;
    await ref.read(sentenceControllerProvider.notifier).loadOrGenerateToday(
          dailySentenceGenerated: isGenerated,
        );

    _initialLoadCompleted = true;

    if (!mounted) return;

    // 履歴を更新
    ref.invalidate(allSentencesProvider);
  }

  void _showFirstTimeGuideDialog() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.school, size: 40),
        title: const Text('学習の流れ'),
        content: const Text(
          'まずは例文を3つ学習しましょう！\n'
          '3つ完了するとまとめクイズに挑戦できます。\n\n'
          '次回からは5例文ごとにまとめクイズが出題されます。',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      LearningScreen(showAppIconNotifier: _showAppIcon),
      const HistoryScreen(),
      const SettingsScreen(),
    ];

    return Scaffold(
      body: Stack(
        children: [
          IndexedStack(index: _currentIndex, children: screens),
          ValueListenableBuilder<bool>(
            valueListenable: _showAppIcon,
            builder: (context, show, child) {
              if (!show) return const SizedBox.shrink();
              return child!;
            },
            child: Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              left: 12,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.asset('assets/appicon.png', width: 40, height: 40),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() {
            _currentIndex = index;
          });
          _logCurrentTabScreen(index: index);
        },
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.school_outlined),
            selectedIcon: Icon(Icons.school),
            label: '学習',
          ),
          const NavigationDestination(
            icon: Icon(Icons.history_outlined),
            selectedIcon: Icon(Icons.history),
            label: '履歴',
          ),
          const NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: '設定',
          ),
        ],
      ),
    );
  }

  void _logCurrentTabScreen({int? index}) {
    final currentIndex = index ?? _currentIndex;
    final screenName = switch (currentIndex) {
      0 => 'learning',
      1 => 'history',
      2 => 'settings',
      _ => 'home',
    };

    // IndexedStack は route が増えないため、タブ切り替えは手動で screen_view を送る。
    unawaited(
      ref.read(analyticsServiceProvider).logScreenView(
            screenName: screenName,
            screenClass: 'HomeTab',
          ),
    );
  }
}

enum _LearningStage { sentence, quiz, summaryQuiz }

bool _changedFromNoRemainingToAvailable(
  AsyncValue<int>? previous,
  AsyncValue<int> next,
) {
  final previousRemaining = previous?.valueOrNull;
  final nextRemaining = next.valueOrNull;
  return previousRemaining != null &&
      nextRemaining != null &&
      previousRemaining <= 0 &&
      nextRemaining > 0;
}

class LearningScreen extends ConsumerStatefulWidget {
  final ValueNotifier<bool> showAppIconNotifier;

  const LearningScreen({super.key, required this.showAppIconNotifier});

  @override
  ConsumerState<LearningScreen> createState() => _LearningScreenState();
}

class _LearningScreenState extends ConsumerState<LearningScreen> {
  static const int _summaryQuizThreshold = 5;
  static const int _firstTimeSummaryQuizThreshold = 3;
  static const String _completedCountKey = 'learning_completed_count';
  _LearningStage _stage = _LearningStage.sentence;
  ThaiSentence? _quizSentence;
  int _completedCount = 0;
  bool _firstSummaryQuizCompleted = true;

  int get _currentThreshold =>
      _firstSummaryQuizCompleted ? _summaryQuizThreshold : _firstTimeSummaryQuizThreshold;

  @override
  void initState() {
    super.initState();
    _loadCompletedCount();
    _loadFirstSummaryQuizFlag();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _restoreSavedSummaryQuizIfNeeded();
      ref.listenManual(sentenceControllerProvider, (prev, next) {
        if (prev is SentenceStateLoading &&
            next is SentenceStateSuccess &&
            next.generated &&
            _stage == _LearningStage.sentence) {
          ref.read(quizControllerProvider.notifier).prepareQuiz(next.sentence);
        }
      });
    });
  }

  Future<void> _loadFirstSummaryQuizFlag() async {
    final prefs = await SharedPreferences.getInstance();
    final completed =
        prefs.getBool(AppConfig.prefKeyFirstSummaryQuizCompleted) ?? false;
    if (mounted && completed != _firstSummaryQuizCompleted) {
      setState(() => _firstSummaryQuizCompleted = completed);
    }
  }

  Future<void> _markFirstSummaryQuizCompleted() async {
    _firstSummaryQuizCompleted = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AppConfig.prefKeyFirstSummaryQuizCompleted, true);
  }

  Future<void> _restoreSavedSummaryQuizIfNeeded() async {
    final quizNotifier = ref.read(quizControllerProvider.notifier);
    final hasSavedSummaryQuiz = await quizNotifier.hasSavedSummaryQuiz();
    if (!mounted || !hasSavedSummaryQuiz || _stage != _LearningStage.sentence) {
      return;
    }

    _setStage(_LearningStage.summaryQuiz);
    await quizNotifier.generateAndStartQuiz();
  }

  Future<void> _loadCompletedCount() async {
    final prefs = await SharedPreferences.getInstance();
    final count = prefs.getInt(_completedCountKey) ?? 0;
    if (mounted && count != _completedCount) {
      setState(() => _completedCount = count);
    }
  }

  Future<void> _setCompletedCount(int count) async {
    _completedCount = count;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_completedCountKey, count);
  }

  void _setStage(_LearningStage newStage) {
    setState(() => _stage = newStage);
    widget.showAppIconNotifier.value = newStage == _LearningStage.sentence;
  }

  void _returnToLearningTop() {
    final sentence = _quizSentence;
    if (sentence != null) {
      ref.read(sentenceControllerProvider.notifier).showSentence(sentence);
    }
    _setStage(_LearningStage.sentence);
  }

  Future<void> _generateNextLearningSentence() async {
    _setStage(_LearningStage.sentence);
    final genParams = ref.read(generationParamsProvider);
    await ref
        .read(sentenceControllerProvider.notifier)
        .generateSentence(generationParams: genParams);
    final sentenceState = ref.read(sentenceControllerProvider);
    if (sentenceState is SentenceStateSuccess) {
      ref
          .read(quizControllerProvider.notifier)
          .prepareQuiz(sentenceState.sentence);
      ref.invalidate(allSentencesProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(remainingSentencesProvider, (prev, next) {
      if (_changedFromNoRemainingToAvailable(prev, next) &&
          mounted &&
          _stage != _LearningStage.sentence) {
        _setStage(_LearningStage.sentence);
      }
    });

    return switch (_stage) {
      _LearningStage.sentence => TodayScreen(
          onStartQuiz: (sentence) {
            _quizSentence = sentence;
            final quizNotifier = ref.read(quizControllerProvider.notifier);
            final quizState = ref.read(quizControllerProvider);

            // 既に回答中/結果表示中ならそのまま再表示
            if (quizState is QuizAnswering || quizState is QuizShowResult) {
              // nothing
            } else {
              quizNotifier.startLearningQuiz(sentence);
            }
            _setStage(_LearningStage.quiz);
          },
        ),
      _LearningStage.quiz => Scaffold(
          appBar: AppBar(
            title: const Text('学習'),
            automaticallyImplyLeading: false,
          ),
          body: QuizScreen(
            showAppBar: false,
            title: 'クイズ',
            learningSentence: _quizSentence,
            onBackToLearningStart: _returnToLearningTop,
            nextButtonLabel: '次の例文へ',
            onOptionalChallenge: _completedCount + 1 >= _currentThreshold
                ? () async {
                    await _setCompletedCount(0);
                    ref.read(quizControllerProvider.notifier).reset();
                    ref
                        .read(quizControllerProvider.notifier)
                        .generateAndStartQuiz();
                    _setStage(_LearningStage.summaryQuiz);
                  }
                : null,
            onNextSentence: () async {
              await _setCompletedCount(_completedCount + 1);
              await _generateNextLearningSentence();
            },
          ),
        ),
      _LearningStage.summaryQuiz => Scaffold(
          appBar: AppBar(
            title: const Text('まとめクイズ'),
            automaticallyImplyLeading: false,
          ),
          body: QuizScreen(
            showAppBar: false,
            title: 'まとめクイズ',
            showVocabScoreTransition: true,
            onNextSentence: () async {
              if (!_firstSummaryQuizCompleted) {
                await _markFirstSummaryQuizCompleted();
              }
              await _setCompletedCount(0);
              await _generateNextLearningSentence();
            },
          ),
        ),
    };
  }
}

/// Today's sentence screen
class TodayScreen extends ConsumerStatefulWidget {
  final ValueChanged<ThaiSentence>? onStartQuiz;

  const TodayScreen({
    super.key,
    this.onStartQuiz,
  });

  /// デフォルトの挨拶例文（サンプル、履歴には保存されない）
  static final ThaiSentence _defaultGreetingSentence = ThaiSentence(
    id: null, // idがnullなのでDBには保存されない
    thaiText: 'สวัสดีครับ',
    pronunciation: 'sawatdii khrap',
    japaneseTranslation: 'こんにちは（男性の場合）',
    wordBreakdowns: [
      WordBreakdown(
        wordText: 'สวัสดี',
        pronunciation: 'sà-wàt-dii',
        meaning: 'こんにちは、さようなら',
        grammaticalRole: '挨拶語',
        wordOrder: 0,
        syllables: [
          Syllable(
            text: 'สวัส',
            initialConsonant: 'สว',
            consonantClass: 'high',
            tone: 'low',
            toneMark: 'none',
            syllableType: 'dead',
          ),
          Syllable(
            text: 'ดี',
            initialConsonant: 'ด',
            consonantClass: 'middle',
            tone: 'mid',
            toneMark: 'none',
            syllableType: 'live',
          ),
        ],
      ),
      WordBreakdown(
        wordText: 'ครับ',
        pronunciation: 'khráp',
        meaning: '〜です（男性の丁寧な語尾）',
        grammaticalRole: '語尾詞',
        wordOrder: 1,
        syllables: [
          Syllable(
            text: 'ครับ',
            initialConsonant: 'คร',
            consonantClass: 'low',
            tone: 'high',
            toneMark: 'none',
            syllableType: 'dead',
            hasShortVowel: true,
          ),
        ],
      ),
    ],
    context: SentenceContext(
      topic: '日常的な挨拶',
      style: '口語体',
      emotion: '丁寧、フォーマル',
      usageScenarios: '朝昼晩いつでも使える基本的な挨拶。女性の場合は「ค่ะ」を使います。',
    ),
    createdAt: null,
    generationTier: 'free',
  );

  @override
  ConsumerState<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends ConsumerState<TodayScreen> {
  @override
  Widget build(BuildContext context) {
    ref.listen(vocabStatsProvider, (prev, next) {
      final prevVocab = prev?.valueOrNull?.estimatedVocab ?? 0;
      final nextVocab = next.valueOrNull?.estimatedVocab ?? 0;
      if (nextVocab > prevVocab) {
        _checkLevelUp(nextVocab);
      }
    });
    final sentenceState = ref.watch(sentenceControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('学習')),
      body: _buildSentenceContent(context, sentenceState),
    );
  }

  /// Build sentence content based on state
  Widget _buildSentenceContent(BuildContext context, SentenceState state) {
    if (state is SentenceStateLoading) {
      return _buildLoadingState();
    } else if (state is SentenceStateSuccess) {
      return _buildSuccessState(context, state.sentence);
    } else if (state is SentenceStateError) {
      return _buildErrorState(context, state.message);
    } else if (state is SentenceStateEmpty) {
      return _buildEmptyState(context);
    } else {
      return _buildEmptyState(context);
    }
  }

  /// Build loading state
  Widget _buildLoadingState() {
    return const Center(
      child: Card(
        child: Padding(
          padding: EdgeInsets.all(AppConfig.defaultPadding * 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('次の例文を準備中...'),
              SizedBox(height: 24),
              LoadingTipCarousel(),
            ],
          ),
        ),
      ),
    );
  }

  /// Build success state with single sentence
  Widget _buildSuccessState(BuildContext context, ThaiSentence sentence) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              AppConfig.defaultPadding,
              AppConfig.defaultPadding,
              AppConfig.defaultPadding,
              AppConfig.defaultPadding,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildTargetWordsSection(context, sentence),
                const SizedBox(height: 12),
                _buildSentenceCard(context, sentence),
              ],
            ),
          ),
        ),
        // 確認クイズ — 下部固定
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppConfig.defaultPadding,
            0,
            AppConfig.defaultPadding,
            AppConfig.defaultPadding,
          ),
          child: _buildLearningFlowActions(context, sentence),
        ),
      ],
    );
  }

  Widget _buildTargetWordsSection(
    BuildContext context,
    ThaiSentence sentence,
  ) {
    final targetWords = sentence.targetWords;
    if (targetWords == null || targetWords.isEmpty) {
      return const SizedBox.shrink();
    }

    final breakdownMap = {
      for (final wb in sentence.wordBreakdowns) wb.wordText: wb,
    };

    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            '今日の学習単語',
            style: theme.textTheme.titleSmall?.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        ...targetWords.map((word) {
          final wb = breakdownMap[word] ??
              breakdownMap['$wordๆ'] ??
              (word.endsWith('ๆ')
                  ? breakdownMap[word.replaceAll('ๆ', '')]
                  : null);
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Card(
              color: cs.secondaryContainer.withValues(alpha: 0.5),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: cs.outline.withValues(alpha: 0.2),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                word,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (wb != null) ...[
                                const SizedBox(width: 8),
                                Text(
                                  wb.pronunciation,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: cs.primary.withValues(alpha: 0.8),
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ],
                            ],
                          ),
                          if (wb != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              wb.meaning,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: cs.onSecondaryContainer,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (wb != null)
                      IconButton(
                        icon: Icon(
                          Icons.volume_up_outlined,
                          size: 20,
                          color: cs.primary,
                        ),
                        onPressed: () {
                          ref.read(ttsServiceProvider).speak(word);
                        },
                        visualDensity: VisualDensity.compact,
                        tooltip: '発音を再生',
                      ),
                  ],
                ),
              ),
            ),
          );
        }),
        Padding(
          padding: const EdgeInsets.only(left: 4, top: 4, bottom: 4),
          child: Row(
            children: [
              Icon(
                Icons.arrow_downward_rounded,
                size: 16,
                color: cs.onSurfaceVariant.withValues(alpha: 0.5),
              ),
              const SizedBox(width: 4),
              Text(
                'この単語を使った例文',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLearningFlowActions(
    BuildContext context,
    ThaiSentence sentence,
  ) {
    return FilledButton.icon(
      onPressed: () => widget.onStartQuiz?.call(sentence),
      icon: const Icon(Icons.quiz),
      label: const Text('確認クイズへ'),
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 14),
        minimumSize: const Size.fromHeight(56),
      ),
    );
  }

  /// Build a sentence card (shared between single and batch views)
  Widget _buildSentenceCard(BuildContext context, ThaiSentence sentence) {
    final borderRadius = BorderRadius.circular(AppConfig.cardBorderRadius);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          InkWell(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  settings: const RouteSettings(name: DetailScreen.routeName),
                  builder: (context) => DetailScreen(
                    sentence: sentence,
                    source: 'today',
                  ),
                ),
              );
            },
            borderRadius: borderRadius,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppConfig.defaultPadding * 1.5,
                AppConfig.defaultPadding * 2.5,
                AppConfig.defaultPadding * 1.5,
                AppConfig.defaultPadding * 1.5,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Thai text with play button
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text.rich(
                          _buildHighlightedThaiText(
                            sentence.thaiText,
                            sentence.targetWords ?? [],
                            Theme.of(context)
                                    .textTheme
                                    .headlineMedium
                                    ?.copyWith(
                                        fontWeight: FontWeight.w500,
                                        height: 1.5,
                                        fontSize: 32) ??
                                const TextStyle(fontSize: 32),
                            Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.volume_up,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        onPressed: () {
                          unawaited(
                            ref.read(analyticsServiceProvider).logPlayTts(
                                  contentType: 'sentence',
                                  text: sentence.thaiText,
                                  sentenceId: sentence.id,
                                  source: 'today_sentence',
                                ),
                          );
                          ref.read(ttsServiceProvider).speak(sentence.thaiText);
                        },
                        tooltip: '全文を再生',
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Pronunciation
                  Text(
                    sentence.pronunciation,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .primary
                              .withValues(alpha: 0.8),
                          fontStyle: FontStyle.italic,
                        ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    sentence.japaneseTranslation,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Icon(
                      Icons.chevron_right,
                      size: 20,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurfaceVariant
                          .withValues(alpha: 0.45),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            top: 0,
            right: 0,
            child: _buildSentenceTierBadge(context, sentence),
          ),
          if (sentence.id != null)
            Positioned(
              top: 8,
              left: 8,
              child: GestureDetector(
                onTap: () async {
                  await ref
                      .read(sentenceRepositoryProvider)
                      .toggleFavorite(sentence.id!, !sentence.isFavorite);
                  final updated =
                      sentence.copyWith(isFavorite: !sentence.isFavorite);
                  ref
                      .read(sentenceControllerProvider.notifier)
                      .showSentence(updated);
                },
                child: Icon(
                  sentence.isFavorite ? Icons.favorite : Icons.favorite_border,
                  size: 24,
                  color: sentence.isFavorite
                      ? Colors.red
                      : Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.4),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSentenceTierBadge(
    BuildContext context,
    ThaiSentence sentence,
  ) {
    final cs = Theme.of(context).colorScheme;
    final hasStoredTier = sentence.generationTier != null;
    final showPremium = hasStoredTier
        ? sentence.wasGeneratedWithPremiumSpec
        : _legacySentenceLooksPremium();
    final foreground = cs.onSurfaceVariant;

    return Tooltip(
      message: showPremium ? 'Premium例文' : 'Free例文',
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 5, 12, 5),
        decoration: BoxDecoration(
          color: showPremium
              ? cs.primaryContainer.withValues(alpha: 0.72)
              : cs.surfaceContainerHighest.withValues(alpha: 0.86),
          border: Border(
            left: BorderSide(
              color: cs.outlineVariant.withValues(alpha: 0.55),
            ),
            bottom: BorderSide(
              color: cs.outlineVariant.withValues(alpha: 0.55),
            ),
          ),
          borderRadius: const BorderRadius.only(
            bottomLeft: Radius.circular(8),
          ),
        ),
        child: Text(
          showPremium ? 'Premium' : 'Free',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontSize: 11,
                color: foreground.withValues(alpha: 0.82),
                fontWeight: FontWeight.w400,
              ),
        ),
      ),
    );
  }

  bool _legacySentenceLooksPremium() {
    return (ref.watch(isPremiumRealtimeProvider).valueOrNull ??
            ref.watch(isPremiumProvider)) ==
        true;
  }

  static const _levelThresholds = [100, 300, 600, 1500];
  static const _prefKeyLastLevel = 'last_vocab_level';

  String _vocabLevel(int vocab) => vocabLevel(vocab);

  Future<void> _checkLevelUp(int vocab) async {
    final crossedThreshold = _levelThresholds.any((t) => vocab >= t);
    if (!crossedThreshold) return;

    final level = _vocabLevel(vocab);
    final prefs = await SharedPreferences.getInstance();
    final lastLevel = prefs.getString(_prefKeyLastLevel) ?? '入門';

    if (level == lastLevel) return;

    // レベルが上がった場合のみ（下がった場合は無視）
    final lastIndex =
        _levelThresholds.indexWhere((t) => t > (_thresholdForLevel(lastLevel)));
    final newIndex =
        _levelThresholds.indexWhere((t) => t > (_thresholdForLevel(level)));
    final effectiveLastIndex =
        lastIndex == -1 ? _levelThresholds.length : lastIndex;
    final effectiveNewIndex =
        newIndex == -1 ? _levelThresholds.length : newIndex;
    if (effectiveNewIndex <= effectiveLastIndex) return;

    await prefs.setString(_prefKeyLastLevel, level);
  }

  int _thresholdForLevel(String level) {
    switch (level) {
      case '入門':
        return 0;
      case '初級':
        return 100;
      case '初中級':
        return 300;
      case '中級':
        return 600;
      case '上級':
        return 1500;
      default:
        return 0;
    }
  }

  /// Build error state
  Widget _buildErrorState(BuildContext context, String message) {
    final isQuotaError = message.contains('上限');
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppConfig.defaultPadding * 2),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isQuotaError ? Icons.lock_outline : Icons.error_outline,
              size: 64,
              color: isQuotaError
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 24),
            Text(
              message,
              style: Theme.of(context).textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
            if (isQuotaError) ...[
              const SizedBox(height: 12),
              Text(
                nextResetText(),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.64),
                    ),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 24),
            if (isQuotaError) ...[
              if (!ref.watch(isPremiumProvider))
                FilledButton.icon(
                  onPressed: () => PaywallBottomSheet.show(
                    context,
                    source: 'sentence_quota_error',
                  ),
                  icon: const Icon(Icons.star),
                  label: const Text('プレミアムにアップグレード'),
                ),
            ] else ...[
              FilledButton.icon(
                onPressed: () {
                  final genParams = ref.read(generationParamsProvider);
                  ref
                      .read(sentenceControllerProvider.notifier)
                      .generateSentence(generationParams: genParams);
                },
                icon: const Icon(Icons.refresh),
                label: const Text('再試行'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Build empty state with default greeting sentence
  Widget _buildEmptyState(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppConfig.defaultPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // サンプル例文のラベル
          Card(
            color: Theme.of(context).colorScheme.secondaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(AppConfig.defaultPadding),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 20,
                    color: Theme.of(context).colorScheme.onSecondaryContainer,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'サンプル例文（履歴には保存されません）',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSecondaryContainer,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _buildSentenceCard(context, TodayScreen._defaultGreetingSentence),
        ],
      ),
    );
  }

  TextSpan _buildHighlightedThaiText(
    String text,
    List<String> targetWords,
    TextStyle baseStyle,
    Color highlightColor,
  ) {
    if (targetWords.isEmpty) {
      return TextSpan(text: text, style: baseStyle);
    }
    final sorted = [...targetWords]
      ..sort((a, b) => b.length.compareTo(a.length));
    final pattern = sorted.map(RegExp.escape).join('|');
    final regex = RegExp(pattern);
    final spans = <TextSpan>[];
    var lastEnd = 0;
    final highlightStyle = baseStyle.copyWith(
      color: highlightColor,
      fontWeight: FontWeight.bold,
      backgroundColor: highlightColor.withValues(alpha: 0.2),
    );
    for (final match in regex.allMatches(text)) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(text: text.substring(lastEnd, match.start)));
      }
      spans.add(TextSpan(text: match.group(0), style: highlightStyle));
      lastEnd = match.end;
    }
    if (lastEnd < text.length) {
      spans.add(TextSpan(text: text.substring(lastEnd)));
    }
    return TextSpan(style: baseStyle, children: spans);
  }
}
