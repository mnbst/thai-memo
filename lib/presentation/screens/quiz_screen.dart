import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/config/app_config.dart';
import '../../data/models/quiz_question.dart';
import '../../data/models/thai_sentence.dart';
import '../providers/analytics_provider.dart';
import '../providers/quiz_provider.dart';
import '../providers/remaining_quota_provider.dart';
import '../providers/review_prompt_provider.dart';
import '../providers/subscription_provider.dart';
import '../providers/tts_provider.dart';
import '../providers/vocab_stats_provider.dart';
import '../widgets/coach_mark_overlay.dart';
import '../widgets/loading_tip_carousel.dart';
import '../widgets/topic_picker.dart';
import 'detail_screen.dart';
import 'paywall_screen.dart';

const String _summaryQuizVocabBeforeKey = 'summary_quiz_vocab_before';
const int _maxSummaryQuizVocabIncrease = 50;

class QuizScreen extends ConsumerStatefulWidget {
  static const routeName = 'quiz';

  final bool showAppBar;
  final String title;
  final ThaiSentence? learningSentence;
  final VoidCallback? onBackToLearningStart;
  final Future<void> Function()? onNextSentence;
  final Future<void> Function()? onOptionalChallenge;
  final String nextButtonLabel;
  final String optionalChallengeLabel;
  final bool showVocabScoreTransition;

  /// true の場合、「次の例文へ」ボタンを非活性化する。
  /// 初回まとめクイズへ誘導するため、スキップして次の例文を生成する動線を塞ぐ。
  final bool disableNextSentence;

  const QuizScreen({
    super.key,
    this.showAppBar = true,
    this.title = '今日のクイズ',
    this.learningSentence,
    this.onBackToLearningStart,
    this.onNextSentence,
    this.onOptionalChallenge,
    this.nextButtonLabel = '次の例文へ',
    this.optionalChallengeLabel = '5問チャレンジする',
    this.showVocabScoreTransition = false,
    this.disableNextSentence = false,
  });

  @override
  ConsumerState<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends ConsumerState<QuizScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _celebrationController;
  late final List<_ConfettiParticle> _confettiParticles;
  int? _vocabBeforeQuiz;

  /// 「次のテーマ」チップの位置特定用（初回コーチマーク表示に使用）。
  final GlobalKey _nextTopicKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    final rng = math.Random(7);
    _celebrationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _confettiParticles = List.generate(18, (index) {
      final angle = math.pi * (1.08 + rng.nextDouble() * 0.84);
      final distance = 44.0 + rng.nextDouble() * 58;
      return _ConfettiParticle(
        dx: math.cos(angle) * distance,
        dy: math.sin(angle) * distance,
        color: [
          const Color(0xFF4F63A0),
          const Color(0xFF7DA7E8),
          const Color(0xFFFFC857),
          const Color(0xFFE76F51),
          const Color(0xFF6BCB77),
        ][index % 5],
        size: 4.0 + rng.nextDouble() * 5,
        rotation: rng.nextDouble() * math.pi,
      );
    });
    ref.listenManual(quizControllerProvider, (prev, next) {
      // クイズ完了時にstatsを再取得
      if (next is QuizSummary) {
        if (next.totalCorrect == next.questions.length) {
          unawaited(SystemSound.play(SystemSoundType.alert));
          _celebrationController.forward(from: 0);
        }
        ref.invalidate(quizStatsProvider);
        if (prev is QuizShowResult) {
          unawaited(_requestReviewAfterQuizCompletion(next));
        }
        if (widget.showVocabScoreTransition) {
          _logSummaryQuizComplete(next);
        }
        _maybeShowNextTopicCoach();
      }
      if (widget.showVocabScoreTransition &&
          next is QuizAnswering &&
          next.index == 0 &&
          prev is! QuizAnswering) {
        _captureVocabBeforeQuiz();
      }
    });
    unawaited(_restoreVocabBeforeQuiz());
  }

  Future<void> _captureVocabBeforeQuiz() async {
    if (_vocabBeforeQuiz != null) return;
    final vocab =
        ref.read(vocabStatsProvider).valueOrNull?.estimatedVocab ??
            (await ref.read(vocabStatsProvider.future)).estimatedVocab;
    if (!mounted || _vocabBeforeQuiz != null) return;
    _vocabBeforeQuiz = vocab;
    if (widget.showVocabScoreTransition) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_summaryQuizVocabBeforeKey, vocab);
    }
  }

  Future<void> _restoreVocabBeforeQuiz() async {
    if (!widget.showVocabScoreTransition || _vocabBeforeQuiz != null) return;
    final quizState = ref.read(quizControllerProvider);
    final shouldRestore = quizState is QuizSummary ||
        (quizState is QuizAnswering && quizState.index > 0);
    if (!shouldRestore) return;

    final prefs = await SharedPreferences.getInstance();
    final vocab = prefs.getInt(_summaryQuizVocabBeforeKey);
    if (!mounted || vocab == null || _vocabBeforeQuiz != null) return;
    setState(() => _vocabBeforeQuiz = vocab);
  }

  void _logSummaryQuizComplete(QuizSummary summary) {
    final vocabAfter =
        ref.read(vocabStatsProvider).valueOrNull?.estimatedVocab;
    unawaited(
      ref.read(analyticsServiceProvider).logSummaryQuizComplete(
            score: summary.totalCorrect,
            questionCount: summary.questions.length,
            vocabBefore: _vocabBeforeQuiz,
            vocabAfter: vocabAfter,
          ),
    );
  }

  /// 結果画面の「次のテーマ」変更チップを初回だけスポットライトで案内する。
  /// チップが表示される（＝次の例文へ進める）場合のみ、1回限り。
  Future<void> _maybeShowNextTopicCoach() async {
    if (widget.onNextSentence == null) return;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(AppConfig.prefKeyNextTopicCoachShown) ?? false) return;

    // サマリー画面が描画され、チップの位置が確定してから表示する。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          ref.read(quizControllerProvider) is! QuizSummary ||
          _nextTopicKey.currentContext == null) {
        return;
      }
      CoachMarkOverlay.show(
        context,
        targetKey: _nextTopicKey,
        title: '次の例文のテーマを選べます',
        message: 'ここをタップすると、次に生成する例文のテーマ（旅行・恋愛など）を変更できます。気分に合わせて学習内容を選びましょう。',
        onDismiss: () {
          unawaited(
            prefs.setBool(AppConfig.prefKeyNextTopicCoachShown, true),
          );
        },
      );
    });
  }

  Future<void> _clearVocabBeforeQuiz() async {
    if (!widget.showVocabScoreTransition) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_summaryQuizVocabBeforeKey);
  }

  @override
  void dispose() {
    CoachMarkOverlay.dismiss();
    _celebrationController.dispose();
    super.dispose();
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

    final body = _buildContent(context, quizState);

    if (!widget.showAppBar) {
      return body;
    }

    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: body,
    );
  }

  Widget _buildContent(BuildContext context, QuizState state) {
    if (widget.showVocabScoreTransition &&
        _vocabBeforeQuiz == null &&
        state is QuizAnswering &&
        state.index == 0) {
      _captureVocabBeforeQuiz();
    }

    if (state is QuizGenerating) {
      return _buildGeneratingState(context);
    }
    if (state is QuizNoSentences) {
      return _buildNoSentencesState(context);
    }
    if (state is QuizError) {
      return _buildErrorState(context, state.message);
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
    return const Center(child: CircularProgressIndicator());
  }

  Widget _buildNoSentencesState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppConfig.defaultPadding * 2),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.menu_book,
                size: 64, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 24),
            Text(
              'まず例文を開きましょう',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'クイズは学習中の例文から出題されます',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
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
            // 上限到達時はアップグレード促しを表示しない
            // （premium もクイズ上限は同じ 5 回/日のため訴求が噛み合わない）
            if (!isQuotaError) ...[
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () {
                  final sentence = widget.learningSentence;
                  if (sentence != null) {
                    ref
                        .read(quizControllerProvider.notifier)
                        .startLearningQuiz(sentence);
                  } else {
                    ref
                        .read(quizControllerProvider.notifier)
                        .generateAndStartQuiz();
                  }
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

  Widget _buildAnsweringState(BuildContext context, QuizAnswering state) {
    final question = state.questions[state.index];
    return _QuizQuestionView(
      question: question,
      questionIndex: state.index,
      totalQuestions: state.questions.length,
      onShowSentence: widget.onBackToLearningStart,
      onAnswer: (choiceIndex, hintLevel, reviewedSentence) {
        ref.read(quizControllerProvider.notifier).answerQuestion(
              choiceIndex,
              hintLevel: hintLevel,
              reviewedSentence: reviewedSentence,
            );
      },
      showHint: widget.learningSentence == null,
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
      showExplanations: widget.learningSentence == null,
      learningNextLabel: widget.nextButtonLabel,
      onLearningNext: widget.onNextSentence,
      onNext: () {
        ref.read(quizControllerProvider.notifier).nextQuestion();
      },
    );
  }

  Widget _buildSummaryState(BuildContext context, QuizSummary state) {
    final isConfirmationQuiz =
        widget.learningSentence != null && state.questions.length == 1;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppConfig.defaultPadding * 2),
      child: Column(
        children: [
          const SizedBox(height: 32),
          state.totalCorrect == state.questions.length
              ? _CrackerCelebration(
                  controller: _celebrationController,
                  particles: _confettiParticles,
                )
              : Icon(
                  Icons.celebration,
                  size: 64,
                  color: Theme.of(context).colorScheme.primary,
                ),
          const SizedBox(height: 24),
          if (widget.showVocabScoreTransition && _vocabBeforeQuiz != null) ...[
            _buildVocabTransitionCard(context, _vocabBeforeQuiz!),
            const SizedBox(height: 16),
          ],
          if (isConfirmationQuiz) ...[
            _buildConfirmationSummaryResult(
              context,
              question: state.questions.first,
              isCorrect: state.answers.first,
            ),
          ] else ...[
            // 各問題の結果一覧
            ...List.generate(state.questions.length, (i) {
              final q = state.questions[i];
              final ok = state.answers[i];
              final selectedIdx = i < state.selectedIndices.length
                  ? state.selectedIndices[i]
                  : 0;
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
                    title: Text(
                      q.correctAnswer,
                      style: const TextStyle(fontSize: 18),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (q.correctAnswerMeaning.isNotEmpty)
                          Text(
                            q.correctAnswerMeaning,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
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
                            showExplanations: widget.learningSentence == null,
                            scrollController: scrollController,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              );
            }),
          ],
          const SizedBox(height: 16),
          // 次の例文のテーマ表示／変更（課金導線）。
          if (widget.onNextSentence != null) ...[
            KeyedSubtree(
              key: _nextTopicKey,
              child: const NextSentenceTopicLabel(
                paywallSource: 'quiz_next_topic',
              ),
            ),
            const SizedBox(height: 8),
          ],
          if (widget.onOptionalChallenge != null) ...[
            FilledButton.icon(
              onPressed: widget.onOptionalChallenge,
              icon: const Icon(Icons.emoji_events),
              label: Text(widget.optionalChallengeLabel),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                minimumSize: const Size.fromHeight(52),
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (widget.onBackToLearningStart != null) ...[
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: widget.onBackToLearningStart,
                    icon: const Icon(Icons.arrow_back, size: 18),
                    label: const Text('例文に戻る'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: widget.onOptionalChallenge != null
                      ? OutlinedButton.icon(
                          onPressed: widget.disableNextSentence
                              ? null
                              : () async {
                                  if (widget.onNextSentence != null) {
                                    unawaited(_clearVocabBeforeQuiz());
                                    await widget.onNextSentence!();
                                  }
                                },
                          icon: const Icon(Icons.arrow_forward, size: 18),
                          label: Text(widget.nextButtonLabel),
                          style: OutlinedButton.styleFrom(
                            backgroundColor: const Color(0xFFEAF2FF),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        )
                      : FilledButton.icon(
                          onPressed: widget.disableNextSentence
                              ? null
                              : () async {
                                  if (widget.onNextSentence != null) {
                                    unawaited(_clearVocabBeforeQuiz());
                                    await widget.onNextSentence!();
                                  }
                                },
                          icon: const Icon(Icons.arrow_forward),
                          label: Text(widget.nextButtonLabel),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                ),
              ],
            ),
          ] else ...[
            FilledButton.icon(
              onPressed: () async {
                if (widget.onNextSentence != null) {
                  unawaited(_clearVocabBeforeQuiz());
                  await widget.onNextSentence!();
                } else {
                  unawaited(_clearVocabBeforeQuiz());
                  ref.read(quizControllerProvider.notifier).reset();
                  Navigator.maybePop(context);
                }
              },
              icon: const Icon(Icons.arrow_forward),
              label: Text(widget.nextButtonLabel),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildConfirmationSummaryResult(
    BuildContext context, {
    required QuizQuestion question,
    required bool isCorrect,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          color: isCorrect
              ? colorScheme.primaryContainer
              : colorScheme.errorContainer,
          child: Padding(
            padding: const EdgeInsets.all(AppConfig.defaultPadding),
            child: Row(
              children: [
                Icon(
                  isCorrect ? Icons.check_circle : Icons.cancel,
                  color: isCorrect ? colorScheme.primary : colorScheme.error,
                  size: 32,
                ),
                const SizedBox(width: 12),
                Text(
                  isCorrect ? '正解！' : '不正解',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color:
                            isCorrect ? colorScheme.primary : colorScheme.error,
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppConfig.defaultPadding * 1.5),
            child: _QuizAnswerWordRow(
              question: question,
              analyticsSource: 'quiz_summary_confirmation',
              showSentenceContext: false,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildVocabTransitionCard(BuildContext context, int before) {
    final vocabAsync = ref.watch(vocabStatsProvider);
    final isPremium = ref.watch(isPremiumProvider);
    return vocabAsync.when(
      data: (vocab) {
        final cap = isPremium ? (1 << 31) : 100;
        final after = vocab.estimatedVocab.clamp(0, cap);
        final savedBefore = before.clamp(0, cap);
        final displayBefore =
            savedBefore == 0 && after > _maxSummaryQuizVocabIncrease
                ? after
                : savedBefore;
        final diff = after - displayBefore;
        return Card(
          color:
              diff > 0 ? Theme.of(context).colorScheme.primaryContainer : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
            child: Column(
              children: [
                if (diff > 0) ...[
                  _VocabScoreIncreaseHeader(diff: diff),
                  const SizedBox(height: 12),
                ] else ...[
                  Text('語彙スコア', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 12),
                ],
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
                if (diff < 0) ...[
                  const SizedBox(height: 6),
                  Text(
                    '$diff語',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                          Icons.celebration,
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

class _VocabScoreIncreaseHeader extends StatefulWidget {
  final int diff;

  const _VocabScoreIncreaseHeader({required this.diff});

  @override
  State<_VocabScoreIncreaseHeader> createState() =>
      _VocabScoreIncreaseHeaderState();
}

class _VocabScoreIncreaseHeaderState extends State<_VocabScoreIncreaseHeader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _sparkleProgress;
  late final Animation<double> _badgeScale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..forward();
    unawaited(SystemSound.play(SystemSoundType.click));
    _sparkleProgress = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    _badgeScale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.92, end: 1.08)
            .chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 55,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.08, end: 1.0)
            .chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 45,
      ),
    ]).animate(_controller);
  }

  @override
  void didUpdateWidget(_VocabScoreIncreaseHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.diff != widget.diff) {
      _controller.forward(from: 0);
      unawaited(SystemSound.play(SystemSoundType.click));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final primary = colorScheme.primary;
    final onContainer = colorScheme.onPrimaryContainer;

    return SizedBox(
      height: 104,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Stack(
            alignment: Alignment.center,
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _VocabSparklePainter(
                    progress: _sparkleProgress.value,
                    color: primary,
                  ),
                ),
              ),
              Transform.scale(
                scale: _badgeScale.value,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  decoration: BoxDecoration(
                    color: colorScheme.surface.withValues(alpha: 0.62),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: primary.withValues(alpha: 0.22),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TweenAnimationBuilder<int>(
                        tween: IntTween(begin: 0, end: widget.diff),
                        duration: const Duration(milliseconds: 850),
                        curve: Curves.easeOutCubic,
                        builder: (context, value, _) {
                          return Text(
                            '+$value語',
                            style: Theme.of(context)
                                .textTheme
                                .displaySmall
                                ?.copyWith(
                                  color: primary,
                                  fontWeight: FontWeight.bold,
                                ),
                          );
                        },
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '語彙スコアアップ！',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              color: onContainer,
                            ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _VocabSparklePainter extends CustomPainter {
  final double progress;
  final Color color;

  const _VocabSparklePainter({
    required this.progress,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    final sparkles = [
      (const Offset(0.14, 0.34), 5.0, 0.00),
      (const Offset(0.24, 0.72), 3.5, 0.18),
      (const Offset(0.76, 0.28), 4.5, 0.10),
      (const Offset(0.86, 0.66), 3.8, 0.26),
      (const Offset(0.50, 0.16), 3.2, 0.34),
    ];

    for (final sparkle in sparkles) {
      final localProgress =
          ((progress - sparkle.$3) / (1 - sparkle.$3)).clamp(0.0, 1.0);
      if (localProgress <= 0) continue;

      final opacity = math.sin(localProgress * math.pi).clamp(0.0, 1.0);
      final center = Offset(
        size.width * sparkle.$1.dx,
        size.height * sparkle.$1.dy,
      );
      final radius = sparkle.$2 * (0.7 + localProgress * 0.55);
      paint.color = color.withValues(alpha: opacity * 0.72);
      _drawSparkle(canvas, paint, center, radius);
    }
  }

  void _drawSparkle(Canvas canvas, Paint paint, Offset center, double radius) {
    final path = Path();
    for (var i = 0; i < 8; i++) {
      final angle = -math.pi / 2 + i * math.pi / 4;
      final r = i.isEven ? radius : radius * 0.38;
      final point = center + Offset(math.cos(angle) * r, math.sin(angle) * r);
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_VocabSparklePainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}

class _CrackerCelebration extends StatelessWidget {
  final AnimationController controller;
  final List<_ConfettiParticle> particles;

  const _CrackerCelebration({
    required this.controller,
    required this.particles,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SizedBox(
      width: 132,
      height: 112,
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, child) {
          final burst = Curves.easeOutCubic.transform(controller.value);
          final pop = Curves.elasticOut.transform(
            controller.value.clamp(0.0, 0.72) / 0.72,
          );

          return Stack(
            alignment: Alignment.center,
            children: [
              CustomPaint(
                size: const Size(132, 112),
                painter: _ConfettiPainter(
                  particles: particles,
                  progress: burst,
                ),
              ),
              Transform.rotate(
                angle: -0.45 + math.sin(controller.value * math.pi * 2) * 0.06,
                child: Transform.scale(
                  scale: 0.72 + pop * 0.28,
                  child: Icon(
                    Icons.celebration,
                    size: 64,
                    color: colorScheme.primary,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ConfettiParticle {
  final double dx;
  final double dy;
  final Color color;
  final double size;
  final double rotation;

  const _ConfettiParticle({
    required this.dx,
    required this.dy,
    required this.color,
    required this.size,
    required this.rotation,
  });
}

class _ConfettiPainter extends CustomPainter {
  final List<_ConfettiParticle> particles;
  final double progress;

  const _ConfettiPainter({
    required this.particles,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final origin = Offset(size.width / 2 - 10, size.height / 2 + 12);
    final opacity = (1.0 - progress).clamp(0.0, 1.0);

    for (final particle in particles) {
      final fall = 26 * progress * progress;
      final offset = origin +
          Offset(
            particle.dx * progress,
            particle.dy * progress + fall,
          );
      final paint = Paint()
        ..color = particle.color.withValues(alpha: opacity)
        ..style = PaintingStyle.fill;

      canvas.save();
      canvas.translate(offset.dx, offset.dy);
      canvas.rotate(particle.rotation + progress * math.pi * 1.8);
      final rect = Rect.fromCenter(
        center: Offset.zero,
        width: particle.size * 0.8,
        height: particle.size * 1.8,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(1)),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

// ==================== 出題ビュー ====================

class _QuizQuestionView extends StatefulWidget {
  final QuizQuestion question;
  final int questionIndex;
  final int totalQuestions;
  final VoidCallback? onShowSentence;
  final void Function(
    int choiceIndex,
    int hintLevel,
    bool reviewedSentence,
  ) onAnswer;
  final bool showHint;

  const _QuizQuestionView({
    required this.question,
    required this.questionIndex,
    required this.totalQuestions,
    this.onShowSentence,
    required this.onAnswer,
    this.showHint = true,
  });

  @override
  State<_QuizQuestionView> createState() => _QuizQuestionViewState();
}

class _QuizQuestionViewState extends State<_QuizQuestionView> {
  int _hintLevel = 0;
  bool _reviewedSentence = false;

  @override
  void didUpdateWidget(_QuizQuestionView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.questionIndex != widget.questionIndex) {
      _hintLevel = 0;
      _reviewedSentence = false;
    }
  }

  Future<void> _showSentenceDetail(ThaiSentence sentence) async {
    setState(() => _reviewedSentence = true);
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DetailScreen(
          sentence: sentence,
          source: 'quiz_review_button',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final question = widget.question;
    final hasPronunciation = question.sentencePronunciation.isNotEmpty;
    final hasTranslation = question.japaneseTranslation.isNotEmpty;
    final maxHintLevel = (hasPronunciation ? 1 : 0) + (hasTranslation ? 1 : 0);
    final sentenceDetail = question.sentenceDetail;
    final canReviewSentence =
        widget.totalQuestions > 1 && sentenceDetail != null;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppConfig.defaultPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.totalQuestions > 1) ...[
            // 進捗
            Row(
              children: [
                Text(
                    '問題 ${widget.questionIndex + 1} / ${widget.totalQuestions}',
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
          ] else ...[
            Text(
              '下線部に入る単語を選んでください',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
          ],
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
          // ヒント1: ローマ字読み（問題文の下、正解部分を空欄に）
          if (_hintLevel >= 1 && hasPronunciation) ...[
            const SizedBox(height: 8),
            Builder(builder: (context) {
              final blanked = question.blankSentencePronunciation.isNotEmpty
                  ? question.blankSentencePronunciation
                  : question.pronunciation.isNotEmpty
                      ? question.sentencePronunciation
                          .replaceFirst(question.pronunciation, '___')
                      : '';
              if (blanked.isEmpty ||
                  blanked == question.sentencePronunciation) {
                return const SizedBox.shrink();
              }
              return Text(
                blanked,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontStyle: FontStyle.italic,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                textAlign: TextAlign.center,
              );
            }),
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
          const SizedBox(height: 16),
          // 4択
          ...List.generate(question.choices.length, (i) {
            final choicePronunciation = i < question.choicePronunciations.length
                ? question.choicePronunciations[i]
                : '';
            final showChoicePronunciation =
                _hintLevel >= 1 && choicePronunciation.isNotEmpty;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: SizedBox(
                height: showChoicePronunciation ? 84 : 56,
                child: ElevatedButton(
                  onPressed: () =>
                      widget.onAnswer(i, _hintLevel, _reviewedSentence),
                  style: ElevatedButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(AppConfig.cardBorderRadius),
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        question.choices[i],
                        style: const TextStyle(fontSize: 24),
                      ),
                      if (showChoicePronunciation) ...[
                        const SizedBox(height: 2),
                        Text(
                          choicePronunciation,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    fontStyle: FontStyle.italic,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primary
                                        .withValues(alpha: 0.75),
                                  ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          }),
          if (canReviewSentence) ...[
            const SizedBox(height: 4),
            TextButton(
              onPressed: () => _showSentenceDetail(sentenceDetail),
              child: Text(
                _reviewedSentence ? '例文を復習済み' : '例文を復習する',
                style: TextStyle(
                  fontSize: 15,
                  color: Theme.of(context)
                      .colorScheme
                      .outline,
                ),
              ),
            ),
          ] else if (widget.showHint && _hintLevel < maxHintLevel) ...[
            const SizedBox(height: 4),
            FilledButton.tonalIcon(
              onPressed: () => setState(() => _hintLevel = maxHintLevel),
              icon: const Icon(Icons.lightbulb_outline),
              label: const Text('ヒント'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ],
          if (widget.onShowSentence != null) ...[
            const SizedBox(height: 4),
            FilledButton.tonalIcon(
              onPressed: widget.onShowSentence,
              icon: const Icon(Icons.menu_book_outlined),
              label: const Text('例文を確認'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ==================== 結果表示ビュー ====================

class _QuizAnswerWordRow extends ConsumerWidget {
  final QuizQuestion question;
  final String analyticsSource;
  final bool showSentenceContext;

  const _QuizAnswerWordRow({
    required this.question,
    required this.analyticsSource,
    this.showSentenceContext = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showSentenceContext) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Flexible(
                child: Text(
                  question.thaiText,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w500,
                        height: 1.45,
                      ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon:
                    Icon(Icons.volume_up, size: 20, color: colorScheme.primary),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () {
                  unawaited(
                    ref.read(analyticsServiceProvider).logPlayTts(
                          contentType: 'sentence',
                          text: question.thaiText,
                          sentenceId: question.sentenceId,
                          source: analyticsSource,
                        ),
                  );
                  ref.read(ttsServiceProvider).speak(question.thaiText);
                },
                tooltip: '例文を再生',
              ),
            ],
          ),
          if (question.sentencePronunciation.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              question.sentencePronunciation,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
          if (question.japaneseTranslation.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              question.japaneseTranslation,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ],
          const Divider(height: 28),
        ],
        Row(
          children: [
            Flexible(
              child: Text(
                question.correctAnswer,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
            const SizedBox(width: 8),
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
              tooltip: '単語を再生',
            ),
          ],
        ),
        if (question.correctAnswerMeaning.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            question.correctAnswerMeaning,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
          ),
        ],
        if (question.pronunciation.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            question.pronunciation,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ],
    );
  }
}

bool _hasQuizExplanationContent(QuizQuestion question) {
  return question.explanation.trim().isNotEmpty ||
      question.dummyReasons.any((reason) => reason.trim().isNotEmpty);
}

class _QuizExplanationSection extends StatelessWidget {
  final QuizQuestion question;

  const _QuizExplanationSection({required this.question});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasCorrectReason = question.explanation.trim().isNotEmpty;
    final hasIncorrectReasons =
        question.dummyReasons.any((reason) => reason.trim().isNotEmpty);

    if (!hasCorrectReason && !hasIncorrectReasons) {
      return const SizedBox.shrink();
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppConfig.defaultPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hasCorrectReason) ...[
              _QuizReasonHeader(
                icon: Icons.check_circle,
                label: '正解理由',
                color: colorScheme.primary,
              ),
              const SizedBox(height: 8),
              Text(
                question.explanation,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
            if (hasCorrectReason && hasIncorrectReasons)
              const SizedBox(height: 16),
            if (hasIncorrectReasons) ...[
              _QuizReasonHeader(
                icon: Icons.cancel,
                label: '不正解理由',
                color: colorScheme.error,
              ),
              const SizedBox(height: 8),
              ..._buildIncorrectReasonRows(context),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _buildIncorrectReasonRows(BuildContext context) {
    final rows = <Widget>[];

    for (var i = 0; i < question.dummyReasons.length; i++) {
      final reason = question.dummyReasons[i].trim();
      if (reason.isEmpty) {
        continue;
      }

      rows.add(
        Padding(
          padding: EdgeInsets.only(
            bottom: i == question.dummyReasons.length - 1 ? 0 : 8,
          ),
          child: Text(
            reason,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      );
    }

    return rows;
  }
}

class _QuizReasonHeader extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _QuizReasonHeader({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 6),
        Text(
          label,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
        ),
      ],
    );
  }
}

class _QuizResultView extends StatelessWidget {
  final QuizQuestion question;
  final int questionIndex;
  final int totalQuestions;
  final int selectedIndex;
  final bool isCorrect;
  final bool showExplanations;
  final String learningNextLabel;
  final Future<void> Function()? onLearningNext;
  final VoidCallback onNext;

  const _QuizResultView({
    required this.question,
    required this.questionIndex,
    required this.totalQuestions,
    required this.selectedIndex,
    required this.isCorrect,
    required this.showExplanations,
    required this.learningNextLabel,
    this.onLearningNext,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppConfig.defaultPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (totalQuestions > 1) ...[
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
          ],
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
          // 正解ワード
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppConfig.defaultPadding * 1.5),
              child: Center(
                child: _QuizAnswerWordRow(
                  question: question,
                  analyticsSource: 'quiz_result',
                  showSentenceContext: showExplanations,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (showExplanations && _hasQuizExplanationContent(question)) ...[
            _QuizExplanationSection(question: question),
            const SizedBox(height: 16),
          ],
          if (showExplanations) ...[
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
          if (!showExplanations) ...[
            FilledButton.icon(
              onPressed: () async {
                final next = onLearningNext;
                if (next != null) {
                  await next();
                } else {
                  onNext();
                }
              },
              icon: const Icon(Icons.arrow_forward),
              label: Text(learningNextLabel),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ==================== 結果詳細ボトムシート ====================

class _QuizResultDetail extends StatelessWidget {
  final QuizQuestion question;
  final int selectedIndex;
  final bool isCorrect;
  final bool showExplanations;
  final ScrollController scrollController;

  const _QuizResultDetail({
    required this.question,
    required this.selectedIndex,
    required this.isCorrect,
    required this.showExplanations,
    required this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
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
        // 正解ワード
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppConfig.defaultPadding * 1.5),
            child: Center(
              child: _QuizAnswerWordRow(
                question: question,
                analyticsSource: 'quiz_result_detail',
                showSentenceContext: showExplanations,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (showExplanations && _hasQuizExplanationContent(question)) ...[
          _QuizExplanationSection(question: question),
          const SizedBox(height: 16),
        ],
        if (showExplanations)
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
      ],
    );
  }
}
