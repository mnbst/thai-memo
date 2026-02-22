import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../data/models/syllable.dart';
import '../../data/models/thai_sentence.dart';
import '../../data/models/word_breakdown.dart';
import '../../services/fcm_service.dart';
import '../providers/sentence_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/tts_provider.dart';
import 'detail_screen.dart';
import 'history_screen.dart';
import 'review_screen.dart';
import 'settings_screen.dart';

/// Home screen with bottom navigation
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkFirstLaunchAndLoadSentence();
    });
    // 通知タップ時に復習タブへ切り替え
    FcmService.instance.onReviewDataReceived = () {
      if (mounted) {
        setState(() {
          _currentIndex = 1; // 復習タブ
        });
      }
    };
  }

  /// Check if first launch and load sentence
  Future<void> _checkFirstLaunchAndLoadSentence() async {
    final isFirstLaunch = ref.read(isFirstLaunchProvider);

    if (isFirstLaunch) {
      // Navigate to settings on first launch
      setState(() {
        _currentIndex = 3; // Settings tab
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('まいにちタイ語へようこそ！'),
            duration: Duration(seconds: 3),
          ),
        );
      }
    } else {
      // Load most recent sentence
      ref.read(sentenceControllerProvider.notifier).loadMostRecent();
    }
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      const TodayScreen(),
      const ReviewScreen(),
      const HistoryScreen(),
      const SettingsScreen(),
    ];

    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.today_outlined),
            selectedIcon: Icon(Icons.today),
            label: '例文生成',
          ),
          NavigationDestination(
            icon: Icon(Icons.lightbulb_outline),
            selectedIcon: Icon(Icons.lightbulb),
            label: '復習',
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
class TodayScreen extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final sentenceState = ref.watch(sentenceControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('例文生成')),
      body: _buildSentenceContent(context, ref, sentenceState),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _generateNewSentence(context, ref),
        icon: const Icon(Icons.refresh),
        label: const Text('新しい例文を生成'),
      ),
    );
  }

  /// Build sentence content based on state
  Widget _buildSentenceContent(
    BuildContext context,
    WidgetRef ref,
    SentenceState state,
  ) {
    if (state is SentenceStateLoading) {
      return _buildLoadingState();
    } else if (state is SentenceStateSuccess) {
      return _buildSuccessState(context, ref, state.sentence);
    } else if (state is SentenceStateError) {
      return _buildErrorState(context, state.message);
    } else if (state is SentenceStateEmpty) {
      return _buildEmptyState(context, ref);
    } else {
      return _buildEmptyState(context, ref);
    }
  }

  /// Build loading state
  Widget _buildLoadingState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('例文を生成中...'),
        ],
      ),
    );
  }

  /// Build success state with sentence
  Widget _buildSuccessState(BuildContext context, WidgetRef ref, sentence) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppConfig.defaultPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Sentence card
          Card(
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
                                ?.copyWith(fontWeight: FontWeight.w500, height: 1.5, fontSize: 32),
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
                            color: Theme.of(
                              context,
                            ).colorScheme.primary.withValues(alpha: 0.8),
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
                          color: Theme.of(
                            context,
                          ).colorScheme.primary.withValues(alpha: 0.6),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'タップして詳細を見る',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.primary.withValues(alpha: 0.6),
                              ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Quick info
          _buildQuickInfo(context, sentence),
        ],
      ),
    );
  }

  /// Build quick info section
  Widget _buildQuickInfo(BuildContext context, sentence) {
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppConfig.defaultPadding * 2),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 24),
            Text(
              'エラーが発生しました',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              style: Theme.of(context).textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  /// Build empty state with default greeting sentence
  Widget _buildEmptyState(BuildContext context, WidgetRef ref) {
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
          // デフォルトの挨拶例文を表示
          Card(
            child: InkWell(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) =>
                        DetailScreen(sentence: _defaultGreetingSentence),
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
                            _defaultGreetingSentence.thaiText,
                            style: Theme.of(context)
                                .textTheme
                                .headlineMedium
                                ?.copyWith(fontWeight: FontWeight.w500, height: 1.5, fontSize: 32),
                          ),
                        ),
                        IconButton(
                          icon: Icon(
                            Icons.volume_up,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          onPressed: () {
                            ref.read(ttsServiceProvider).speak(_defaultGreetingSentence.thaiText);
                          },
                          tooltip: '全文を再生',
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Pronunciation
                    Text(
                      _defaultGreetingSentence.pronunciation,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: Theme.of(
                              context,
                            ).colorScheme.primary.withValues(alpha: 0.8),
                            fontStyle: FontStyle.italic,
                          ),
                    ),
                    const SizedBox(height: 16),
                    // Japanese translation
                    Text(
                      _defaultGreetingSentence.japaneseTranslation,
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
                          color: Theme.of(
                            context,
                          ).colorScheme.primary.withValues(alpha: 0.6),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'タップして詳細を見る',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.primary.withValues(alpha: 0.6),
                              ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Quick info
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppConfig.defaultPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '単語数: ${_defaultGreetingSentence.wordBreakdowns.length}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  if (_defaultGreetingSentence.context?.topic != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      '場面: ${_defaultGreetingSentence.context!.topic}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Generate new sentence
  Future<void> _generateNewSentence(BuildContext context, WidgetRef ref) async {
    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(AppConfig.defaultPadding * 2),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('例文を生成中...'),
              ],
            ),
          ),
        ),
      ),
    );

    // Generate sentence
    final generationParams = ref.read(generationParamsProvider);
    await ref.read(sentenceControllerProvider.notifier).generateSentence(
          generationParams: generationParams,
        );

    // Close loading dialog
    if (context.mounted) {
      Navigator.pop(context);
    }

    // Show result message
    final state = ref.read(sentenceControllerProvider);
    if (context.mounted) {
      if (state is SentenceStateSuccess) {
        // Refresh history providers to show the new sentence
        ref.invalidate(allSentencesProvider);
        ref.invalidate(favoriteSentencesProvider);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('新しい例文を生成しました！'),
            backgroundColor: Theme.of(context).colorScheme.primary,
          ),
        );
      } else if (state is SentenceStateError) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(state.message), backgroundColor: Theme.of(context).colorScheme.error),
        );
      }
    }
  }
}
