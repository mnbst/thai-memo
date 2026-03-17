import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../data/models/syllable.dart';
import '../../data/models/thai_sentence.dart';
import '../../data/models/word_breakdown.dart';
import '../../services/fcm_service.dart';
import '../providers/sentence_provider.dart';
import '../providers/quiz_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/tts_provider.dart';
import '../providers/remaining_quota_provider.dart';
import '../providers/vocab_stats_provider.dart';
import '../widgets/loading_tip_carousel.dart';
import 'detail_screen.dart';
import 'history_screen.dart';
import 'onboarding_screen.dart';
import 'quiz_screen.dart';
import 'settings_screen.dart';

/// Home screen with bottom navigation
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with WidgetsBindingObserver {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkFirstLaunchAndLoadSentence();
    });
    // 通知タップ時に例文タブへ切り替え
    FcmService.instance.onSentenceTabRequested = () {
      if (mounted) {
        setState(() {
          _currentIndex = 0; // 例文タブ
        });
      }
    };

    // 保留中の通知遷移があれば実行
    FcmService.instance.markHomeReady();
  }

  @override
  void dispose() {
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
    // バッチ生成中・ローディング中なら二重生成を防ぐためスキップ
    final currentState = ref.read(sentenceControllerProvider);
    if (currentState is SentenceStateBatchLoading ||
        currentState is SentenceStateLoading) {
      return;
    }

    final data = await ref.read(userDocProvider.future);
    final isGenerated = (data?['daily_sentence_generated'] as bool?) ?? false;
    if (!isGenerated) {
      ref.read(sentenceControllerProvider.notifier).loadOrGenerateToday(
            dailySentenceGenerated: false,
          );
      ref.invalidate(allSentencesProvider);
      ref.invalidate(favoriteSentencesProvider);
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
    }

    // FCM初期化＋通知権限リクエスト（オンボーディング後 or 既存ユーザー初回表示時）
    await FcmService.instance.initialize();
    await FcmService.instance.requestPermissionAndRegisterToken();

    if (!mounted) return;

    // Firestoreフラグを取得し、未生成なら自動生成、済みなら最新を表示
    final data2 = await ref.read(userDocProvider.future);
    final isGenerated = (data2?['daily_sentence_generated'] as bool?) ?? false;
    await ref.read(sentenceControllerProvider.notifier).loadOrGenerateToday(
          dailySentenceGenerated: isGenerated,
        );

    if (!mounted) return;

    // 履歴を更新
    ref.invalidate(allSentencesProvider);
    ref.invalidate(favoriteSentencesProvider);
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      const TodayScreen(),
      const QuizScreen(),
      const HistoryScreen(),
      const SettingsScreen(),
    ];

    return Scaffold(
      body: Stack(
        children: [
          IndexedStack(index: _currentIndex, children: screens),
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 12,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset('assets/appicon.png', width: 40, height: 40),
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
          if (index == 1) {
            ref.read(quizControllerProvider.notifier).loadQuiz();
          }
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.today_outlined),
            selectedIcon: Icon(Icons.today),
            label: '例文',
          ),
          NavigationDestination(
            icon: Icon(Icons.quiz_outlined),
            selectedIcon: Icon(Icons.quiz),
            label: 'クイズ',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_outlined),
            selectedIcon: Icon(Icons.history),
            label: '履歴',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: '設定',
          ),
        ],
      ),
    );
  }
}

/// Today's sentence screen
class TodayScreen extends ConsumerStatefulWidget {
  const TodayScreen({super.key});

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
    isFavorite: false,
  );

  @override
  ConsumerState<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends ConsumerState<TodayScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sentenceState = ref.watch(sentenceControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('今日のタイ語')),
      body: _buildSentenceContent(context, sentenceState),
      floatingActionButton: _buildGenerateButton(context),
    );
  }

  /// Build sentence content based on state
  Widget _buildSentenceContent(BuildContext context, SentenceState state) {
    if (state is SentenceStateLoading) {
      return _buildLoadingState();
    } else if (state is SentenceStateBatchLoading) {
      return _buildBatchLoadingState();
    } else if (state is SentenceStateBatchSuccess) {
      return _buildBatchSuccessState(context, state.sentences);
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
              Text('例文を生成中...'),
              SizedBox(height: 24),
              LoadingTipCarousel(),
            ],
          ),
        ),
      ),
    );
  }

  /// Batch loading state
  Widget _buildBatchLoadingState() {
    return const Center(
      child: Card(
        child: Padding(
          padding: EdgeInsets.all(AppConfig.defaultPadding * 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('例文を生成中...'),
              SizedBox(height: 8),
              Text(
                'しばらくお待ちください',
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
              SizedBox(height: 24),
              LoadingTipCarousel(),
            ],
          ),
        ),
      ),
    );
  }

  /// Build batch success state with PageView
  Widget _buildBatchSuccessState(
    BuildContext context,
    List<ThaiSentence> sentences,
  ) {
    return Column(
      children: [
        // Vocab stats
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppConfig.defaultPadding,
            AppConfig.defaultPadding,
            AppConfig.defaultPadding,
            0,
          ),
          child: _buildVocabStats(context),
        ),
        // Page indicator
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppConfig.defaultPadding,
            vertical: 8,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '${_currentPage + 1} / ${sentences.length}',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ],
          ),
        ),
        // Dot indicators
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(sentences.length, (i) {
            return AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: i == _currentPage ? 20 : 8,
              height: 8,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                color: i == _currentPage
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: 0.25),
              ),
            );
          }),
        ),
        const SizedBox(height: 8),
        // PageView of sentences
        Expanded(
          child: PageView.builder(
            controller: _pageController,
            itemCount: sentences.length,
            onPageChanged: (index) {
              setState(() => _currentPage = index);
            },
            itemBuilder: (context, index) {
              final sentence = sentences[index];
              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  AppConfig.defaultPadding,
                  4,
                  AppConfig.defaultPadding,
                  AppConfig.defaultPadding + 20,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildSentenceCard(context, sentence),
                    const SizedBox(height: 16),
                    _buildQuickInfo(context, sentence),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// Build success state with single sentence
  Widget _buildSuccessState(BuildContext context, ThaiSentence sentence) {
    return Column(
      children: [
        // Vocab stats — 上部固定表示
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppConfig.defaultPadding,
            AppConfig.defaultPadding,
            AppConfig.defaultPadding,
            0,
          ),
          child: _buildVocabStats(context),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              AppConfig.defaultPadding,
              AppConfig.defaultPadding,
              AppConfig.defaultPadding,
              AppConfig.defaultPadding + 80,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildSentenceCard(context, sentence),
                const SizedBox(height: 16),
                _buildQuickInfo(context, sentence),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Build a sentence card (shared between single and batch views)
  Widget _buildSentenceCard(BuildContext context, ThaiSentence sentence) {
    return Card(
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => DetailScreen(sentence: sentence),
            ),
          );
        },
        borderRadius: BorderRadius.circular(AppConfig.cardBorderRadius),
        child: Padding(
          padding: const EdgeInsets.all(AppConfig.defaultPadding * 1.5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Thai text with play button
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      sentence.thaiText,
                      style: Theme.of(context)
                          .textTheme
                          .headlineMedium
                          ?.copyWith(
                              fontWeight: FontWeight.w500,
                              height: 1.5,
                              fontSize: 32),
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.volume_up,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    onPressed: () {
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
              // Japanese translation
              Text(
                sentence.japaneseTranslation,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 16),
              // Tap hint
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 16,
                    color: Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: 0.6),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'タップして詳細を見る',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .primary
                              .withValues(alpha: 0.6),
                        ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Build vocab stats card
  Widget _buildVocabStats(BuildContext context) {
    final statsAsync = ref.watch(vocabStatsProvider);
    return statsAsync.when(
      data: (stats) {
        final onContainer = Theme.of(context).colorScheme.onPrimaryContainer;
        return Card(
          color: Theme.of(context).colorScheme.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppConfig.defaultPadding * 1.5,
              vertical: AppConfig.defaultPadding,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.auto_graph, size: 16, color: onContainer),
                const SizedBox(width: 4),
                Text(
                  'あなたの推定語彙数',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: onContainer,
                      ),
                ),
                const SizedBox(width: 12),
                Text(
                  '${stats.estimatedVocab}',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        color: onContainer,
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(width: 4),
                Text(
                  '語',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: onContainer.withValues(alpha: 0.7),
                      ),
                ),
              ],
            ),
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (e, st) {
        debugPrint('vocabStatsProvider error: $e\n$st');
        return Text('vocabStats error: $e',
            style: const TextStyle(color: Colors.red, fontSize: 12));
      },
    );
  }

  /// Build quick info section
  Widget _buildQuickInfo(BuildContext context, ThaiSentence sentence) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppConfig.defaultPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '単語数: ${sentence.wordBreakdowns.length}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (sentence.context?.topic != null) ...[
              const SizedBox(height: 8),
              Text(
                '場面: ${sentence.context!.topic}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ],
        ),
      ),
    );
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
            if (isQuotaError) _buildVocabStats(context),
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
            const SizedBox(height: 24),
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
          const SizedBox(height: 16),
          _buildQuickInfo(context, TodayScreen._defaultGreetingSentence),
        ],
      ),
    );
  }

  /// Build generate button — hidden when remaining=0
  Widget? _buildGenerateButton(BuildContext context) {
    final sentenceState = ref.watch(sentenceControllerProvider);
    // バッチ生成完了後・ローディング中はFAB非表示
    if (sentenceState is SentenceStateBatchSuccess ||
        sentenceState is SentenceStateBatchLoading ||
        sentenceState is SentenceStateLoading) {
      return null;
    }

    final remainingAsync = ref.watch(remainingSentencesProvider);
    final remaining = remainingAsync.valueOrNull;

    // remaining=0 → FAB非表示
    if (remaining != null && remaining <= 0) return null;

    return FloatingActionButton.extended(
      onPressed: () => _generateBatch(context),
      icon: const Icon(Icons.auto_awesome),
      label: remaining != null ? Text('例文生成（$remaining件）') : const Text('例文生成'),
    );
  }

  /// Premium: batch generate all remaining sentences
  Future<void> _generateBatch(BuildContext context) async {
    _currentPage = 0;
    await ref
        .read(sentenceControllerProvider.notifier)
        .generateBatchSentences();

    final state = ref.read(sentenceControllerProvider);
    if (context.mounted) {
      if (state is SentenceStateBatchSuccess) {
        ref.invalidate(allSentencesProvider);
        ref.invalidate(favoriteSentencesProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${state.sentences.length}件の例文を生成しました！'),
            backgroundColor: Theme.of(context).colorScheme.primary,
          ),
        );
      } else if (state is SentenceStateError) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(state.message),
              backgroundColor: Theme.of(context).colorScheme.error),
        );
      }
    }
  }
}
