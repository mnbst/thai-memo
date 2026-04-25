import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/config/app_config.dart';
import '../../data/models/quiz_question.dart';
import '../providers/analytics_provider.dart';
import '../providers/quiz_provider.dart';
import '../providers/remaining_quota_provider.dart';
import '../providers/review_prompt_provider.dart';
import '../providers/subscription_provider.dart';
import '../providers/vocab_stats_provider.dart';
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
  int? _vocabBeforeQuiz;

  @override
  void initState() {
    super.initState();
    ref.listenManual(quizControllerProvider, (prev, next) {
      // クイズ完了時にstatsを再取得
      if (next is QuizSummary) {
        ref.invalidate(quizStatsProvider);
        if (prev is QuizShowResult) {
          unawaited(_requestReviewAfterQuizCompletion(next));
        }
      }
      // クイズ開始時の語彙スコアを記録
      if (next is QuizAnswering && next.index == 0 && prev is! QuizAnswering) {
        final vocab =
            ref.read(vocabStatsProvider).valueOrNull?.estimatedVocab ?? 0;
        setState(() => _vocabBeforeQuiz = vocab);
      }
    });
  }

  Future<void> _requestReviewAfterQuizCompletion(QuizSummary summary) async {
    await Future<void>.delayed(const Duration(seconds: 2));
    if (!mounted || ref.read(quizControllerProvider) is! QuizSummary) {
      return;
    }

    final statsData = QuizStatsData.fromDatabase(summary.stats);
    await ref.read(reviewPromptServiceProvider).maybeRequestAfterQuizCompleted(
          sessionCorrect: summary.totalCorrect,
          sessionTotal: summary.questions.length,
          totalAnswered: statsData.totalAnswered,
        );
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
          const SizedBox(width: 16),
          Icon(Icons.local_fire_department,
              size: 18, color: const Color(0xFF7F0000)),
          const SizedBox(width: 4),
          Text(
            '${stats.currentStreak}日継続',
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
              '過去に学習した例文から出題されます\n間違えてOK！気軽に挑戦しよう',
              textAlign: TextAlign.center,
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
            if (isQuotaError) ...[
              const SizedBox(height: 8),
              Text(
                nextResetText(),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
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
      onAnswer: (choiceIndex, hintLevel) {
        ref
            .read(quizControllerProvider.notifier)
            .answerQuestion(choiceIndex, hintLevel: hintLevel);
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
    final hintUsedCount =
        (state.hintLevels ?? const []).where((l) => l > 0).length;
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
          const SizedBox(height: 16),
          if (_vocabBeforeQuiz != null)
            _buildVocabTransitionCard(context, _vocabBeforeQuiz!),
          if (_vocabBeforeQuiz != null) const SizedBox(height: 16),
          if (hintUsedCount > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .secondaryContainer
                    .withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(AppConfig.cardBorderRadius),
              ),
              child: Row(
                children: [
                  Icon(Icons.lightbulb_outline,
                      size: 18,
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '$hintUsedCount問でヒントを使用。ヒントなしに挑戦するとより効果的です',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 24),
          // 各問題の結果一覧
          ...List.generate(state.questions.length, (i) {
            final q = state.questions[i];
            final ok = state.answers[i];
            final selectedIdx =
                i < state.selectedIndices.length ? state.selectedIndices[i] : 0;
            final hintLevel =
                i < (state.hintLevels?.length ?? 0) ? state.hintLevels![i] : 0;
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
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'キーワード: ${q.correctAnswer}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      if (q.japaneseTranslation.isNotEmpty)
                        Text(
                          q.japaneseTranslation,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      if (hintLevel > 0) ...[
                        const SizedBox(height: 6),
                        Text(
                          'ヒント $hintLevel/2',
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                        ),
                      ],
                    ],
                  ),
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

  Widget _buildVocabTransitionCard(BuildContext context, int before) {
    final vocabAsync = ref.watch(vocabStatsProvider);
    final isPremium = ref.watch(isPremiumProvider);
    return vocabAsync.when(
      data: (vocab) {
        final cap = isPremium ? (1 << 31) : 100;
        final after = vocab.estimatedVocab.clamp(0, cap);
        final displayBefore = before.clamp(0, cap);
        if (after == 0) return const SizedBox.shrink();
        final diff = after - displayBefore;
        return Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
            child: Column(
              children: [
                Text('語彙スコア', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '$displayBefore語',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Icon(
                        Icons.arrow_forward,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      '$after語',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ],
                ),
                if (diff != 0) ...[
                  const SizedBox(height: 6),
                  Text(
                    diff > 0 ? '+$diff語' : '$diff語',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: diff > 0
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
                if (!isPremium && after >= 100) ...[
                  const SizedBox(height: 12),
                  const Divider(),
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: () => PaywallBottomSheet.show(
                      context,
                      source: 'quiz_vocab_cap_banner',
                    ),
                    borderRadius: BorderRadius.circular(8),
                    child: Row(
                      children: [
                        Icon(
                          Icons.emoji_events,
                          color: Theme.of(context).colorScheme.primary,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '語彙スコアが上限に達しました',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              Text(
                                'Premiumで続きの成長を記録しよう',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.arrow_forward_ios,
                          size: 14,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
      loading: () => Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 12),
              Text(
                '語彙スコアを計算中...',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
      ),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

// ==================== 出題ビュー ====================

class _QuizQuestionView extends StatefulWidget {
  final QuizQuestion question;
  final int questionIndex;
  final int totalQuestions;
  final void Function(int choiceIndex, int hintLevel) onAnswer;

  const _QuizQuestionView({
    required this.question,
    required this.questionIndex,
    required this.totalQuestions,
    required this.onAnswer,
  });

  @override
  State<_QuizQuestionView> createState() => _QuizQuestionViewState();
}

class _QuizQuestionViewState extends State<_QuizQuestionView> {
  int _hintLevel = 0;

  @override
  void didUpdateWidget(_QuizQuestionView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.questionIndex != widget.questionIndex) {
      _hintLevel = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final question = widget.question;
    final hasPronunciation = question.sentencePronunciation.isNotEmpty;
    final hasTranslation = question.japaneseTranslation.isNotEmpty;
    final maxHintLevel = (hasPronunciation ? 1 : 0) + (hasTranslation ? 1 : 0);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppConfig.defaultPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 進捗
          Row(
            children: [
              Text('問題 ${widget.questionIndex + 1} / ${widget.totalQuestions}',
                  style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              SizedBox(
                width: 100,
                child: LinearProgressIndicator(
                  value: (widget.questionIndex + 1) / widget.totalQuestions,
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
          // ヒント1: ローマ字読み（問題文の下）
          if (_hintLevel >= 1 && hasPronunciation) ...[
            const SizedBox(height: 8),
            Text(
              question.sentencePronunciation,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontStyle: FontStyle.italic,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
          ],
          // ヒント2: 日本語訳（ローマ字の下）
          if (_hintLevel >= 2 && hasTranslation) ...[
            const SizedBox(height: 4),
            Text(
              question.japaneseTranslation,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
          ],
          // ヒントボタン
          if (_hintLevel < maxHintLevel) ...[
            const SizedBox(height: 8),
            Center(
              child: Column(
                children: [
                  OutlinedButton.icon(
                    onPressed: () => setState(() => _hintLevel++),
                    icon: const Icon(Icons.lightbulb_outline, size: 16),
                    label: Text(_hintLevel == 0 ? 'ヒント' : '日本語訳を見る'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor:
                          Theme.of(context).colorScheme.onSurfaceVariant,
                      side: BorderSide(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurfaceVariant
                            .withValues(alpha: 0.4),
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      textStyle: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'ヒントなしで答えるとスコアアップ！',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant
                              .withValues(alpha: 0.6),
                        ),
                  ),
                ],
              ),
            ),
          ] else ...[
            const SizedBox(height: 16),
          ],
          // 4択
          ...List.generate(question.choices.length, (i) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: SizedBox(
                height: 56,
                child: ElevatedButton(
                  onPressed: () => widget.onAnswer(i, _hintLevel),
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

class _QuizExplanationCard extends StatelessWidget {
  final QuizQuestion question;

  const _QuizExplanationCard({
    required this.question,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
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
            if (question.dummyReasons.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('不正解の理由',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              ...question.dummyReasons.map(
                (reason) => Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text('・$reason',
                      style: Theme.of(context).textTheme.bodyMedium),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _QuizAnswerWordRow extends ConsumerWidget {
  final QuizQuestion question;
  final String analyticsSource;

  const _QuizAnswerWordRow({
    required this.question,
    required this.analyticsSource,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('今回のキーワード',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.bold,
                )),
        const SizedBox(height: 4),
        Row(
          children: [
            Flexible(
              child: Text('正解: ${question.correctAnswer}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: colorScheme.primary,
                      )),
            ),
            const SizedBox(width: 4),
            IconButton(
              icon: Icon(Icons.volume_up, size: 20, color: colorScheme.primary),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: () {
                unawaited(
                  ref.read(analyticsServiceProvider).logPlayTts(
                        contentType: 'word',
                        text: question.correctAnswer,
                        sentenceId: question.sentenceId,
                        source: analyticsSource,
                      ),
                );
                ref.read(ttsServiceProvider).speak(question.correctAnswer);
              },
              tooltip: '発音を再生',
            ),
          ],
        ),
        if (question.pronunciation.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text('発音: ${question.pronunciation}',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    fontStyle: FontStyle.italic,
                    color: colorScheme.primary.withValues(alpha: 0.8),
                  )),
        ],
      ],
    );
  }
}

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
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(question.thaiText,
                            style: Theme.of(context)
                                .textTheme
                                .headlineMedium
                                ?.copyWith(
                                    fontWeight: FontWeight.w500,
                                    height: 1.5,
                                    fontSize: 28)),
                      ),
                      IconButton(
                        icon: Icon(Icons.volume_up,
                            color: Theme.of(context).colorScheme.primary),
                        onPressed: () {
                          unawaited(
                            ref.read(analyticsServiceProvider).logPlayTts(
                                  contentType: 'sentence',
                                  text: question.thaiText,
                                  sentenceId: question.sentenceId,
                                  source: 'quiz_result',
                                ),
                          );
                          ref.read(ttsServiceProvider).speak(question.thaiText);
                        },
                        tooltip: '例文を読み上げ',
                      ),
                    ],
                  ),
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
                  _QuizAnswerWordRow(
                    question: question,
                    analyticsSource: 'quiz_result',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // 解説
          _QuizExplanationCard(question: question),
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
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(question.thaiText,
                          style: Theme.of(context)
                              .textTheme
                              .headlineMedium
                              ?.copyWith(
                                  fontWeight: FontWeight.w500,
                                  height: 1.5,
                                  fontSize: 28)),
                    ),
                    IconButton(
                      icon: Icon(Icons.volume_up,
                          color: Theme.of(context).colorScheme.primary),
                      onPressed: () {
                        unawaited(
                          ref.read(analyticsServiceProvider).logPlayTts(
                                contentType: 'sentence',
                                text: question.thaiText,
                                sentenceId: question.sentenceId,
                                source: 'quiz_result_detail',
                              ),
                        );
                        ref.read(ttsServiceProvider).speak(question.thaiText);
                      },
                      tooltip: '例文を読み上げ',
                    ),
                  ],
                ),
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
                _QuizAnswerWordRow(
                  question: question,
                  analyticsSource: 'quiz_result_detail',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        // 解説
        _QuizExplanationCard(question: question),
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
