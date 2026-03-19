import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../data/models/quiz_question.dart';
import '../providers/analytics_provider.dart';
import '../providers/quiz_provider.dart';
import '../providers/remaining_quota_provider.dart';
import '../providers/subscription_provider.dart';
import '../providers/tts_provider.dart';
import '../widgets/loading_tip_carousel.dart';
import 'paywall_screen.dart';

class QuizScreen extends ConsumerStatefulWidget {
  static const routeName = 'quiz';

  const QuizScreen({super.key});

  @override
  ConsumerState<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends ConsumerState<QuizScreen> {
  @override
  void initState() {
    super.initState();
    // クイズ完了時にstatsを再取得
    ref.listenManual(quizControllerProvider, (prev, next) {
      if (next is QuizSummary) {
        ref.invalidate(quizStatsProvider);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final quizState = ref.watch(quizControllerProvider);
    final statsAsync = ref.watch(quizStatsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('今日のクイズ')),
      body: Column(
        children: [
          // 通算正答率バー
          statsAsync.when(
            data: (stats) => _buildStatsBar(context, stats),
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
          // メインコンテンツ
          Expanded(child: _buildContent(context, quizState)),
        ],
      ),
    );
  }

  Widget _buildStatsBar(BuildContext context, QuizStatsData stats) {
    if (stats.totalAnswered == 0) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppConfig.defaultPadding,
        vertical: 8,
      ),
      color:
          Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
      child: Row(
        children: [
          Icon(Icons.emoji_events,
              size: 18, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Text(
            '正答率: ${stats.accuracyPercent}%',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context, QuizState state) {
    if (state is QuizLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state is QuizPending) {
      return _buildPendingState(context, state.questionCount);
    }
    if (state is QuizGenerating) {
      return _buildGeneratingState(context);
    }
    if (state is QuizError) {
      return _buildErrorState(context, state.message);
    }
    if (state is QuizInitial) {
      return _buildEmptyState(context);
    }
    if (state is QuizReady) {
      return _buildReadyState(context, state.questions);
    }
    if (state is QuizAnswering) {
      return _buildAnsweringState(context, state);
    }
    if (state is QuizShowResult) {
      return _buildShowResultState(context, state);
    }
    if (state is QuizSummary) {
      return _buildSummaryState(context, state);
    }
    return _buildEmptyState(context);
  }

  Widget _buildPendingState(BuildContext context, int questionCount) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppConfig.defaultPadding * 2),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.quiz,
                size: 64, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 24),
            const SizedBox(height: 8),
            Text(
              '過去に学習した例文から出題されます',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: () {
                ref
                    .read(quizControllerProvider.notifier)
                    .generateAndStartQuiz();
              },
              icon: const Icon(Icons.play_arrow),
              label: const Text('クイズを始める'),
              style: FilledButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              ),
            ),
            const SizedBox(height: 12),
            _buildRemainingQuizzes(context),
          ],
        ),
      ),
    );
  }

  Widget _buildRemainingQuizzes(BuildContext context) {
    final remaining = ref.watch(remainingQuizzesProvider);
    return remaining.when(
      data: (count) => Text(
        '残り $count 回',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      ),
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Widget _buildGeneratingState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppConfig.defaultPadding * 2),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 24),
            Text('クイズを生成中...', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 32),
            const LoadingTipCarousel(),
          ],
        ),
      ),
    );
  }

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
            Text(message,
                style: Theme.of(context).textTheme.bodyLarge,
                textAlign: TextAlign.center),
            const SizedBox(height: 24),
            if (isQuotaError) ...[
              if (!ref.watch(isPremiumProvider))
                FilledButton.icon(
                  onPressed: () => PaywallBottomSheet.show(
                    context,
                    source: 'quiz_quota_error',
                  ),
                  icon: const Icon(Icons.star),
                  label: const Text('プレミアムにアップグレード'),
                ),
            ] else ...[
              FilledButton.icon(
                onPressed: () {
                  ref
                      .read(quizControllerProvider.notifier)
                      .generateAndStartQuiz();
                },
                icon: const Icon(Icons.refresh),
                label: const Text('もう一度試す'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppConfig.defaultPadding * 2),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.quiz_outlined,
                size: 64,
                color: Theme.of(context)
                    .colorScheme
                    .primary
                    .withValues(alpha: 0.5)),
            const SizedBox(height: 24),
            Text('クイズがありません', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 12),
            Text('通知が届くとクイズが出題されます',
                style: Theme.of(context).textTheme.bodyLarge,
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _buildReadyState(BuildContext context, List<QuizQuestion> questions) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppConfig.defaultPadding * 2),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.quiz,
                size: 64, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 24),
            Text('今日のクイズ', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text('${questions.length}問の穴埋めクイズ',
                style: Theme.of(context).textTheme.bodyLarge),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: () {
                ref.read(quizControllerProvider.notifier).startQuiz();
              },
              icon: const Icon(Icons.play_arrow),
              label: const Text('クイズを始める'),
              style: FilledButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnsweringState(BuildContext context, QuizAnswering state) {
    final question = state.questions[state.index];
    return _QuizQuestionView(
      question: question,
      questionIndex: state.index,
      totalQuestions: state.questions.length,
      onAnswer: (choiceIndex) {
        ref.read(quizControllerProvider.notifier).answerQuestion(choiceIndex);
      },
    );
  }

  Widget _buildShowResultState(BuildContext context, QuizShowResult state) {
    final question = state.questions[state.index];
    return _QuizResultView(
      question: question,
      questionIndex: state.index,
      totalQuestions: state.questions.length,
      selectedIndex: state.selectedIndex,
      isCorrect: state.isCorrect,
      onNext: () {
        ref.read(quizControllerProvider.notifier).nextQuestion();
      },
    );
  }

  Widget _buildSummaryState(BuildContext context, QuizSummary state) {
    final statsData = QuizStatsData.fromDatabase(state.stats);
    final rate = statsData.accuracyPercent;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppConfig.defaultPadding * 2),
      child: Column(
        children: [
          const SizedBox(height: 32),
          Icon(
            state.totalCorrect == state.questions.length
                ? Icons.celebration
                : Icons.assessment,
            size: 64,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 24),
          Text('結果', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppConfig.defaultPadding * 1.5),
              child: Column(
                children: [
                  Text(
                    '${state.totalCorrect} / ${state.questions.length}',
                    style: Theme.of(context).textTheme.displaySmall?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text('正解', style: Theme.of(context).textTheme.bodyLarge),
                  const Divider(height: 32),
                  Text(
                    '通算正答率: $rate%',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          // 各問題の結果一覧
          ...List.generate(state.questions.length, (i) {
            final q = state.questions[i];
            final ok = state.answers[i];
            final selectedIdx =
                i < state.selectedIndices.length ? state.selectedIndices[i] : 0;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Card(
                color: ok
                    ? Theme.of(context)
                        .colorScheme
                        .primaryContainer
                        .withValues(alpha: 0.3)
                    : Theme.of(context)
                        .colorScheme
                        .errorContainer
                        .withValues(alpha: 0.3),
                child: ListTile(
                  leading: Icon(
                    ok ? Icons.check_circle : Icons.cancel,
                    color: ok
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.error,
                  ),
                  title: Text(q.thaiText, style: const TextStyle(fontSize: 16)),
                  subtitle: Text(q.correctAnswer),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      useSafeArea: true,
                      builder: (_) => DraggableScrollableSheet(
                        initialChildSize: 0.85,
                        minChildSize: 0.5,
                        maxChildSize: 0.95,
                        expand: false,
                        builder: (context, scrollController) =>
                            _QuizResultDetail(
                          question: q,
                          selectedIndex: selectedIdx,
                          isCorrect: ok,
                          scrollController: scrollController,
                        ),
                      ),
                    );
                  },
                ),
              ),
            );
          }),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () {
              ref.read(quizControllerProvider.notifier).retryQuiz();
            },
            icon: const Icon(Icons.refresh),
            label: const Text('もう一度挑戦する'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () {
              ref.read(quizControllerProvider.notifier).generateAndStartQuiz();
            },
            icon: const Icon(Icons.auto_awesome),
            label: const Text('新しいクイズ'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
          const SizedBox(height: 8),
          _buildRemainingQuizzes(context),
        ],
      ),
    );
  }
}

// ==================== 出題ビュー ====================

class _QuizQuestionView extends StatelessWidget {
  final QuizQuestion question;
  final int questionIndex;
  final int totalQuestions;
  final void Function(int) onAnswer;

  const _QuizQuestionView({
    required this.question,
    required this.questionIndex,
    required this.totalQuestions,
    required this.onAnswer,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppConfig.defaultPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 進捗
          Row(
            children: [
              Text('問題 ${questionIndex + 1} / $totalQuestions',
                  style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              SizedBox(
                width: 100,
                child: LinearProgressIndicator(
                  value: (questionIndex + 1) / totalQuestions,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          // 指示文
          Text(
            '___に入る適切な単語を選んでください',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 12),
          // 穴埋め例文
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppConfig.defaultPadding * 1.5),
              child: Text(
                question.blankText,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w500, height: 1.5, fontSize: 28),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          const SizedBox(height: 24),
          // 4択
          ...List.generate(question.choices.length, (i) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: SizedBox(
                height: 56,
                child: ElevatedButton(
                  onPressed: () => onAnswer(i),
                  style: ElevatedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(AppConfig.cardBorderRadius),
                    ),
                  ),
                  child: Text(
                    question.choices[i],
                    style: const TextStyle(fontSize: 20),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ==================== 結果表示ビュー ====================

class _QuizResultView extends ConsumerWidget {
  final QuizQuestion question;
  final int questionIndex;
  final int totalQuestions;
  final int selectedIndex;
  final bool isCorrect;
  final VoidCallback onNext;

  const _QuizResultView({
    required this.question,
    required this.questionIndex,
    required this.totalQuestions,
    required this.selectedIndex,
    required this.isCorrect,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppConfig.defaultPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 進捗
          Row(
            children: [
              Text('問題 ${questionIndex + 1} / $totalQuestions',
                  style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              SizedBox(
                width: 100,
                child: LinearProgressIndicator(
                  value: (questionIndex + 1) / totalQuestions,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // 正誤バナー
          Card(
            color: isCorrect
                ? Theme.of(context).colorScheme.primaryContainer
                : Theme.of(context).colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(AppConfig.defaultPadding),
              child: Row(
                children: [
                  Icon(
                    isCorrect ? Icons.check_circle : Icons.cancel,
                    color: isCorrect
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.error,
                    size: 32,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    isCorrect ? '正解！' : '不正解',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: isCorrect
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.error,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // 元の例文
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppConfig.defaultPadding * 1.5),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(question.thaiText,
                      style: Theme.of(context)
                          .textTheme
                          .headlineMedium
                          ?.copyWith(
                              fontWeight: FontWeight.w500,
                              height: 1.5,
                              fontSize: 28)),
                  if (question.sentencePronunciation.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(question.sentencePronunciation,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              fontStyle: FontStyle.italic,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            )),
                  ],
                  if (question.japaneseTranslation.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(question.japaneseTranslation,
                        style: Theme.of(context).textTheme.bodyLarge),
                  ],
                  const Divider(height: 24),
                  Row(
                    children: [
                      Text('正解: ${question.correctAnswer}',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                              )),
                      const SizedBox(width: 4),
                      IconButton(
                        icon: Icon(Icons.volume_up,
                            size: 20,
                            color: Theme.of(context).colorScheme.primary),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () {
                          unawaited(
                            ref.read(analyticsServiceProvider).logPlayTts(
                                  contentType: 'word',
                                  text: question.correctAnswer,
                                  sentenceId: question.sentenceId,
                                  source: 'quiz_result',
                                ),
                          );
                          ref
                              .read(ttsServiceProvider)
                              .speak(question.correctAnswer);
                        },
                        tooltip: '発音を再生',
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text('発音: ${question.pronunciation}',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            fontStyle: FontStyle.italic,
                            color: Theme.of(context)
                                .colorScheme
                                .primary
                                .withValues(alpha: 0.8),
                          )),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // 解説
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppConfig.defaultPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('解説',
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(question.explanation,
                      style: Theme.of(context).textTheme.bodyLarge),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // 4択（正誤ハイライト付き）
          ...List.generate(question.choices.length, (i) {
            final isSelected = i == selectedIndex;
            final isCorrectChoice =
                question.choices[i] == question.correctAnswer;
            Color? bgColor;
            Color? borderColor;
            if (isCorrectChoice) {
              bgColor = Theme.of(context)
                  .colorScheme
                  .primaryContainer
                  .withValues(alpha: 0.5);
              borderColor = Theme.of(context).colorScheme.primary;
            } else if (isSelected && !isCorrect) {
              bgColor = Theme.of(context)
                  .colorScheme
                  .errorContainer
                  .withValues(alpha: 0.5);
              borderColor = Theme.of(context).colorScheme.error;
            }
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                height: 56,
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius:
                      BorderRadius.circular(AppConfig.cardBorderRadius),
                  border: borderColor != null
                      ? Border.all(color: borderColor, width: 2)
                      : Border.all(
                          color: Theme.of(context)
                              .colorScheme
                              .outline
                              .withValues(alpha: 0.3)),
                ),
                alignment: Alignment.center,
                child: Text(
                  question.choices[i],
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight:
                        isCorrectChoice ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
            );
          }),
          const SizedBox(height: 16),
          // 次へボタン
          FilledButton(
            onPressed: onNext,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: Text(
              questionIndex + 1 >= totalQuestions ? '結果を見る' : '次の問題へ',
            ),
          ),
        ],
      ),
    );
  }
}

// ==================== 結果詳細ボトムシート ====================

class _QuizResultDetail extends ConsumerWidget {
  final QuizQuestion question;
  final int selectedIndex;
  final bool isCorrect;
  final ScrollController scrollController;

  const _QuizResultDetail({
    required this.question,
    required this.selectedIndex,
    required this.isCorrect,
    required this.scrollController,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.all(AppConfig.defaultPadding),
      children: [
        // ドラッグハンドル
        Center(
          child: Container(
            width: 32,
            height: 4,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: Theme.of(context)
                  .colorScheme
                  .onSurfaceVariant
                  .withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        // 正誤バナー
        Card(
          color: isCorrect
              ? Theme.of(context).colorScheme.primaryContainer
              : Theme.of(context).colorScheme.errorContainer,
          child: Padding(
            padding: const EdgeInsets.all(AppConfig.defaultPadding),
            child: Row(
              children: [
                Icon(
                  isCorrect ? Icons.check_circle : Icons.cancel,
                  color: isCorrect
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.error,
                  size: 32,
                ),
                const SizedBox(width: 12),
                Text(
                  isCorrect ? '正解！' : '不正解',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: isCorrect
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.error,
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        // 例文カード
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppConfig.defaultPadding * 1.5),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(question.thaiText,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                        height: 1.5,
                        fontSize: 28)),
                if (question.sentencePronunciation.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(question.sentencePronunciation,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            fontStyle: FontStyle.italic,
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          )),
                ],
                if (question.japaneseTranslation.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(question.japaneseTranslation,
                      style: Theme.of(context).textTheme.bodyLarge),
                ],
                const Divider(height: 24),
                Row(
                  children: [
                    Text('正解: ${question.correctAnswer}',
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: Theme.of(context).colorScheme.primary,
                                )),
                    const SizedBox(width: 4),
                    IconButton(
                      icon: Icon(Icons.volume_up,
                          size: 20,
                          color: Theme.of(context).colorScheme.primary),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () {
                        unawaited(
                          ref.read(analyticsServiceProvider).logPlayTts(
                                contentType: 'word',
                                text: question.correctAnswer,
                                sentenceId: question.sentenceId,
                                source: 'quiz_result_detail',
                              ),
                        );
                        ref
                            .read(ttsServiceProvider)
                            .speak(question.correctAnswer);
                      },
                      tooltip: '発音を再生',
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text('発音: ${question.pronunciation}',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontStyle: FontStyle.italic,
                          color: Theme.of(context)
                              .colorScheme
                              .primary
                              .withValues(alpha: 0.8),
                        )),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        // 解説
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppConfig.defaultPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('解説',
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(question.explanation,
                    style: Theme.of(context).textTheme.bodyLarge),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        // 4択（正誤ハイライト付き）
        ...List.generate(question.choices.length, (i) {
          final isSelected = i == selectedIndex;
          final isCorrectChoice = question.choices[i] == question.correctAnswer;
          Color? bgColor;
          Color? borderColor;
          if (isCorrectChoice) {
            bgColor = Theme.of(context)
                .colorScheme
                .primaryContainer
                .withValues(alpha: 0.5);
            borderColor = Theme.of(context).colorScheme.primary;
          } else if (isSelected && !isCorrect) {
            bgColor = Theme.of(context)
                .colorScheme
                .errorContainer
                .withValues(alpha: 0.5);
            borderColor = Theme.of(context).colorScheme.error;
          }
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              height: 56,
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(AppConfig.cardBorderRadius),
                border: borderColor != null
                    ? Border.all(color: borderColor, width: 2)
                    : Border.all(
                        color: Theme.of(context)
                            .colorScheme
                            .outline
                            .withValues(alpha: 0.3)),
              ),
              alignment: Alignment.center,
              child: Text(
                question.choices[i],
                style: TextStyle(
                  fontSize: 20,
                  fontWeight:
                      isCorrectChoice ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
          );
        }),
      ],
    );
  }
}
