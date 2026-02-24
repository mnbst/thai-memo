import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../data/models/quiz_question.dart';
import '../providers/quiz_provider.dart';

class QuizScreen extends ConsumerStatefulWidget {
  const QuizScreen({super.key});

  @override
  ConsumerState<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends ConsumerState<QuizScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(quizControllerProvider.notifier).loadQuiz();
    });
  }

  @override
  Widget build(BuildContext context) {
    final quizState = ref.watch(quizControllerProvider);
    final statsAsync = ref.watch(quizStatsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('クイズ')),
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
      color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
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
              size: 18, color: Theme.of(context).colorScheme.tertiary),
          const SizedBox(width: 4),
          Text(
            '${stats.currentStreak}日連続',
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

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppConfig.defaultPadding * 2),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.quiz_outlined,
                size: 64,
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5)),
            const SizedBox(height: 24),
            Text('クイズがありません',
                style: Theme.of(context).textTheme.headlineSmall),
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
            Text('今日のクイズ',
                style: Theme.of(context).textTheme.headlineSmall),
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
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
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
    final streak = statsData.currentStreak;

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
                  if (streak > 0) ...[
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.local_fire_department,
                            size: 20,
                            color: Theme.of(context).colorScheme.tertiary),
                        const SizedBox(width: 4),
                        Text(
                          '$streak日連続',
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          // 各問題の結果一覧
          ...List.generate(state.questions.length, (i) {
            final q = state.questions[i];
            final ok = state.answers[i];
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
                  title: Text(q.thaiText,
                      style: const TextStyle(fontSize: 16)),
                  subtitle: Text(q.correctAnswer),
                ),
              ),
            );
          }),
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
          // 穴埋め例文
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppConfig.defaultPadding * 1.5),
              child: Text(
                question.blankText,
                style: Theme.of(context)
                    .textTheme
                    .headlineMedium
                    ?.copyWith(fontWeight: FontWeight.w500, height: 1.5, fontSize: 28),
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
                      borderRadius: BorderRadius.circular(AppConfig.cardBorderRadius),
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

class _QuizResultView extends StatelessWidget {
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
                          ?.copyWith(fontWeight: FontWeight.w500, height: 1.5, fontSize: 28)),
                  const SizedBox(height: 8),
                  Text('正解: ${question.correctAnswer}',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: Theme.of(context).colorScheme.primary,
                          )),
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
                          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3)),
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
