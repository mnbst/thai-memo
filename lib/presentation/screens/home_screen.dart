import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../providers/sentence_provider.dart';
import '../providers/settings_provider.dart';
import 'detail_screen.dart';
import 'history_screen.dart';
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
    // Load the most recent sentence on startup
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkFirstLaunchAndLoadSentence();
    });
  }

  /// Check if first launch and load sentence
  Future<void> _checkFirstLaunchAndLoadSentence() async {
    final isFirstLaunch = ref.read(isFirstLaunchProvider);
    final hasApiKey = ref.read(hasApiKeyProvider);

    if (isFirstLaunch || !hasApiKey) {
      // Navigate to settings to configure API key
      setState(() {
        _currentIndex = 2; // Settings tab
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('まず、APIキーを設定してください'),
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
            label: '今日の例文',
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sentenceState = ref.watch(sentenceControllerProvider);
    final hasApiKey = ref.watch(hasApiKeyProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('今日の例文')),
      body: !hasApiKey
          ? _buildNoApiKeyMessage(context)
          : _buildSentenceContent(context, ref, sentenceState),
      floatingActionButton: hasApiKey
          ? FloatingActionButton.extended(
              onPressed: () => _generateNewSentence(context, ref),
              icon: const Icon(Icons.refresh),
              label: const Text('新しい例文を生成'),
            )
          : null,
    );
  }

  /// Build message when API key is not configured
  Widget _buildNoApiKeyMessage(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppConfig.defaultPadding * 2),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.key_off_outlined,
              size: 64,
              color: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 24),
            Text(
              'APIキーが設定されていません',
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              '設定画面でGemini APIキーを入力してください',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.6),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
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
      return _buildEmptyState(context);
    } else {
      return _buildEmptyState(context);
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
                    // Thai text
                    Text(
                      sentence.thaiText,
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w500, height: 1.5),
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
                          style: Theme.of(context).textTheme.bodySmall
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
            if (sentence.context?.situation != null) ...[
              const SizedBox(height: 8),
              Text(
                '場面: ${sentence.context!.situation}',
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

  /// Build empty state
  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppConfig.defaultPadding * 2),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.article_outlined,
              size: 64,
              color: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 24),
            Text(
              'まだ例文がありません',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            Text(
              '下のボタンを押して新しい例文を生成してください',
              style: Theme.of(context).textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
          ],
        ),
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
    await ref.read(sentenceControllerProvider.notifier).generateSentence();

    // Close loading dialog
    if (context.mounted) {
      Navigator.pop(context);
    }

    // Show result message
    final state = ref.read(sentenceControllerProvider);
    if (context.mounted) {
      if (state is SentenceStateSuccess) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('新しい例文を生成しました！'),
            backgroundColor: Colors.green,
          ),
        );
      } else if (state is SentenceStateError) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(state.message), backgroundColor: Colors.red),
        );
      }
    }
  }
}
