import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/config/app_config.dart';
import '../../core/quota_error.dart';
import '../../l10n/app_localizations.dart';
import '../../data/models/quiz_question.dart';
import '../../data/models/thai_sentence.dart';
import '../providers/analytics_provider.dart';
import '../providers/quiz_provider.dart';
import '../providers/remaining_quota_provider.dart';
import '../providers/review_prompt_provider.dart';
import '../providers/tts_provider.dart';
import '../providers/vocab_stats_provider.dart';
import '../widgets/coach_mark_overlay.dart';
import '../widgets/loading_tip_carousel.dart';
import '../widgets/topic_picker.dart';
import 'detail_screen.dart';
import 'paywall_screen.dart';

const String _summaryQuizVocabBeforeKey = 'summary_quiz_vocab_before';
const int _maxSummaryQuizVocabIncrease = 50;
const Duration _correctAnswerAutoAdvanceDelay = Duration(milliseconds: 1200);

class QuizScreen extends ConsumerStatefulWidget {
  static const routeName = 'quiz';

  final bool showAppBar;

  /// null なら「今日のクイズ」。既定値は文言なのでビルド時に解決する。
  final String? title;
  final ThaiSentence? learningSentence;
  final VoidCallback? onBackToLearningStart;
  final Future<void> Function()? onNextSentence;
  final Future<void> Function()? onOptionalChallenge;
  final String? nextButtonLabel;
  final String? optionalChallengeLabel;
  final bool showVocabScoreTransition;

  /// 通知の案内を出してよいタイミングになったことを伝える。
  /// まとめクイズの結果が出たとき、またはその誘導を「あとで」で見送ったとき。
  final VoidCallback? onNotificationCue;

  const QuizScreen({
    super.key,
    this.showAppBar = true,
    this.title,
    this.learningSentence,
    this.onBackToLearningStart,
    this.onNextSentence,
    this.onOptionalChallenge,
    this.nextButtonLabel,
    this.optionalChallengeLabel,
    this.showVocabScoreTransition = false,
    this.onNotificationCue,
  });

  @override
  ConsumerState<QuizScreen> createState() => _QuizScreenState();
}

/// 全問正解時のクラッカー演出の長さ。サマリー画面のコーチマークは
/// これが終わってから出す。
const Duration _celebrationDuration = Duration(milliseconds: 1400);

/// 語彙スコアの加算演出の長さ。クラッカーと同時に始まる。
const Duration _vocabTransitionDuration = Duration(milliseconds: 1200);

/// 演出が終わってから通知の案内へ移るまでの間。増えた数字を読む時間がないまま
/// 画面が切り替わると、何が起きたのか分からなくなる。
const Duration _notificationCuePause = Duration(milliseconds: 600);

/// 結果画面の案内を「あとで」で断ったか。断った直後に別の案内を出すと、
/// 断った意味がなくなる。この起動の間だけ黙る（表示済みフラグは立てないので、
/// 次回起動では出し直される）。
bool _summaryCoachDeclined = false;

/// テスト用に断りの記憶を消す。
@visibleForTesting
void resetSummaryCoachDeclined() => _summaryCoachDeclined = false;

class _QuizScreenState extends ConsumerState<QuizScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _celebrationController;
  late final List<_ConfettiParticle> _confettiParticles;
  int? _vocabBeforeQuiz;

  /// 「次のテーマ」チップの位置特定用（初回コーチマーク表示に使用）。
  final GlobalKey _nextTopicKey = GlobalKey();

  /// まとめクイズ誘導ボタンの位置特定用（初回コーチマーク表示に使用）。
  final GlobalKey _optionalChallengeKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    final rng = math.Random(7);
    _celebrationController = AnimationController(
      vsync: this,
      duration: _celebrationDuration,
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
        // 同じサマリーで何度も走らせない。状態が再通知されるたびに別の案内が
        // 出ると、閉じた直後に次の案内が現れる。
        if (prev is! QuizSummary) {
          _maybeShowChallengeCoach();
          _maybeShowNextTopicCoach();
          unawaited(_cueNotificationCoach());
        }
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
    final vocab = ref.read(vocabStatsProvider).valueOrNull?.estimatedVocab ??
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
        quizState is QuizShowResult ||
        (quizState is QuizAnswering && quizState.index > 0);
    if (!shouldRestore) return;

    final prefs = await SharedPreferences.getInstance();
    final vocab = prefs.getInt(_summaryQuizVocabBeforeKey);
    if (!mounted || vocab == null || _vocabBeforeQuiz != null) return;
    setState(() => _vocabBeforeQuiz = vocab);
  }

  void _logSummaryQuizComplete(QuizSummary summary) {
    final vocabAfter = ref.read(vocabStatsProvider).valueOrNull?.estimatedVocab;
    unawaited(
      ref.read(analyticsServiceProvider).logSummaryQuizComplete(
            score: summary.totalCorrect,
            questionCount: summary.questions.length,
            vocabBefore: _vocabBeforeQuiz,
            vocabAfter: vocabAfter,
          ),
    );
  }

  /// 結果画面の演出が終わるまで待つ。演出中に案内を重ねると、紙吹雪や
  /// 加算アニメーションに隠れて何を勧められたのか残らない。
  /// クラッカーと語彙スコアは同時に始まるので、長い方だけ待てばよい。
  Future<void> _waitForResultAnimations() async {
    final celebration = _celebrationController.isAnimating
        ? _celebrationDuration * (1 - _celebrationController.value)
        : Duration.zero;
    final vocab = widget.showVocabScoreTransition
        ? _vocabTransitionDuration
        : Duration.zero;
    final wait = celebration > vocab ? celebration : vocab;
    if (wait > Duration.zero) await Future<void>.delayed(wait);
  }

  /// まとめクイズの結果が出たら、演出が落ち着いてから通知の案内へ渡す。
  Future<void> _cueNotificationCoach() async {
    if (widget.onNotificationCue == null) return;
    if (!widget.showVocabScoreTransition) return;
    await _waitForResultAnimations();
    await Future<void>.delayed(_notificationCuePause);
    if (!mounted || ref.read(quizControllerProvider) is! QuizSummary) return;
    widget.onNotificationCue!.call();
  }

  /// まとめクイズ誘導ボタンを初回だけスポットライトで案内する。
  /// 確認クイズのサマリーで誘導ボタンが出る場合のみ、1回限り。
  Future<void> _maybeShowChallengeCoach() async {
    if (widget.onOptionalChallenge == null) return;
    if (_summaryCoachDeclined) return;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(AppConfig.prefKeyQuizButtonCoachShown) ?? false) return;

    await _waitForResultAnimations();
    if (!mounted) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          ref.read(quizControllerProvider) is! QuizSummary ||
          _optionalChallengeKey.currentContext == null) {
        return;
      }
      unawaited(prefs.setBool(AppConfig.prefKeyQuizButtonCoachShown, true));
      CoachMarkOverlay.show(
        context,
        targetKey: _optionalChallengeKey,
        id: 'summary_quiz',
        analytics: ref.read(analyticsServiceProvider),
        // まとめクイズは普段は見送れる。ただしこの案内は1回限りなので、
        // ここで「あとで」を許すと、どんなものか一度も知らないまま
        // 二度と案内されない人が出る。初回だけは押させる。
        skippable: false,
        barrierDismissible: false,
        icon: Icons.emoji_events,
        title: L10n.of(context).coachSummaryQuizTitle,
        message: L10n.of(context).coachSummaryQuizMessage,
        emphasis: L10n.of(context).coachSummaryQuizEmphasis,
      );
    });
  }

  /// 結果画面の「次のテーマ」変更チップを初回だけスポットライトで案内する。
  /// チップが表示される（＝次の例文へ進める）場合のみ、1回限り。
  /// 誘導ボタンがある確認クイズのサマリーではコーチが重ならないよう譲る。
  Future<void> _maybeShowNextTopicCoach() async {
    if (widget.onNextSentence == null) return;
    if (widget.onOptionalChallenge != null) return;
    if (_summaryCoachDeclined) return;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(AppConfig.prefKeyNextTopicCoachShown) ?? false) return;

    await _waitForResultAnimations();
    if (!mounted) return;

    // サマリー画面が描画され、チップの位置が確定してから表示する。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          _summaryCoachDeclined ||
          ref.read(quizControllerProvider) is! QuizSummary ||
          _nextTopicKey.currentContext == null) {
        return;
      }
      // 表示時にフラグを立てる。ボタン／チップタップのどちらで閉じても再表示しない。
      unawaited(prefs.setBool(AppConfig.prefKeyNextTopicCoachShown, true));
      CoachMarkOverlay.show(
        context,
        targetKey: _nextTopicKey,
        id: 'next_topic',
        analytics: ref.read(analyticsServiceProvider),
        // 今テーマを変えない人にも逃げ道を出す。
        skippable: true,
        icon: Icons.palette_outlined,
        title: L10n.of(context).coachTopicTitle,
        message: L10n.of(context).coachTopicMessage,
        onDismiss: (action) {
          if (action == 'skipped') _summaryCoachDeclined = true;
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
    // 自分が出したものだけ閉じる。無条件に閉じると、戻り先の画面が既に
    // 出したコーチマークまで消してしまう。
    CoachMarkOverlay.dismissFor(_optionalChallengeKey);
    CoachMarkOverlay.dismissFor(_nextTopicKey);
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
      appBar:
          AppBar(title: Text(widget.title ?? L10n.of(context).quizTodayTitle)),
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
              L10n.of(context).quizOpenSentenceFirst,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              L10n.of(context).quizFromLearningSentence,
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
            Text(
              L10n.of(context).quizGenerating,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 32),
            const LoadingTipCarousel(),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(BuildContext context, String message) {
    final isQuotaError = isQuotaErrorMessage(message);
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
                nextResetText(L10n.of(context)),
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
                        .retryLearningQuiz(sentence);
                  } else {
                    ref
                        .read(quizControllerProvider.notifier)
                        .generateAndStartQuiz();
                  }
                },
                icon: const Icon(Icons.refresh),
                label: Text(L10n.of(context).commonTryAgain),
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
      key: ValueKey('quiz_question_${state.index}'),
      question: question,
      questionIndex: state.index,
      totalQuestions: state.questions.length,
      onShowSentence: widget.onBackToLearningStart,
      onAnswer: (choiceIndex, hintLevel, reviewedSentence) async {
        await ref.read(quizControllerProvider.notifier).answerQuestion(
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
    // 1問の学習クイズは従来どおり結果画面を使う。まとめクイズは、正解時は
    // テンポを優先してインライン表示、不正解時は既存の結果画面で復習する。
    if (widget.learningSentence != null || !state.isCorrect) {
      return _QuizResultView(
        question: question,
        questionIndex: state.index,
        totalQuestions: state.questions.length,
        selectedIndex: state.selectedIndex,
        isCorrect: state.isCorrect,
        showExplanations: widget.learningSentence == null,
        learningNextLabel:
            widget.nextButtonLabel ?? L10n.of(context).learnNextSentence,
        onLearningNext: widget.onNextSentence,
        onNext: () {
          ref.read(quizControllerProvider.notifier).nextQuestion();
        },
      );
    }

    return _QuizQuestionView(
      key: ValueKey('quiz_question_${state.index}'),
      question: question,
      questionIndex: state.index,
      totalQuestions: state.questions.length,
      selectedIndex: state.selectedIndex,
      isCorrect: state.isCorrect,
      showHint: widget.learningSentence == null,
      autoAdvanceCorrect: widget.learningSentence == null,
      onShowSentence: widget.onBackToLearningStart,
      onAnswer: null,
      onNext: () async {
        await ref.read(quizControllerProvider.notifier).nextQuestion();
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
                  : -1;
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
            KeyedSubtree(
              key: _optionalChallengeKey,
              child: FilledButton.icon(
                onPressed: widget.onOptionalChallenge,
                icon: const Icon(Icons.emoji_events),
                label: Text(
                  widget.optionalChallengeLabel ??
                      L10n.of(context).quizOptionalChallenge,
                ),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  minimumSize: const Size.fromHeight(52),
                ),
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
                    label: Text(L10n.of(context).quizBackToSentence),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: widget.onOptionalChallenge != null
                      ? OutlinedButton.icon(
                          onPressed: () async {
                            if (widget.onNextSentence != null) {
                              unawaited(_clearVocabBeforeQuiz());
                              await widget.onNextSentence!();
                            }
                          },
                          icon: const Icon(Icons.arrow_forward, size: 18),
                          label: Text(
                            widget.nextButtonLabel ??
                                L10n.of(context).learnNextSentence,
                          ),
                          style: OutlinedButton.styleFrom(
                            backgroundColor: const Color(0xFFEAF2FF),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        )
                      : FilledButton.icon(
                          onPressed: () async {
                            if (widget.onNextSentence != null) {
                              unawaited(_clearVocabBeforeQuiz());
                              await widget.onNextSentence!();
                            }
                          },
                          icon: const Icon(Icons.arrow_forward),
                          label: Text(
                            widget.nextButtonLabel ??
                                L10n.of(context).learnNextSentence,
                          ),
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
              label: Text(
                widget.nextButtonLabel ?? L10n.of(context).learnNextSentence,
              ),
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
                  isCorrect
                      ? L10n.of(context).quizCorrect
                      : L10n.of(context).quizIncorrect,
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
    // 体験中はサーバー側も語彙上限を外しているので、表示も合わせる。
    final isPremium = ref.watch(effectivePremiumProvider);
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
                  Text(
                    L10n.of(context).vocabScore,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 12),
                ],
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      L10n.of(context).vocabWords(displayBefore),
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
                      L10n.of(context).vocabWords(after),
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
                    L10n.of(context).vocabWordsDelta('$diff'),
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
                                L10n.of(context).vocabScoreCapped,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              Text(
                                L10n.of(context).vocabScorePremiumPitch,
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
                L10n.of(context).vocabScoreCalculating,
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
                            L10n.of(context).vocabWordsDelta('+$value'),
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
                        L10n.of(context).vocabScoreUp,
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

class _QuizQuestionView extends ConsumerStatefulWidget {
  final QuizQuestion question;
  final int questionIndex;
  final int totalQuestions;
  final VoidCallback? onShowSentence;
  final Future<void> Function(
    int choiceIndex,
    int hintLevel,
    bool reviewedSentence,
  )? onAnswer;
  final int? selectedIndex;
  final bool? isCorrect;
  final Future<void> Function()? onNext;
  final bool showHint;
  final bool autoAdvanceCorrect;

  const _QuizQuestionView({
    super.key,
    required this.question,
    required this.questionIndex,
    required this.totalQuestions,
    this.onShowSentence,
    required this.onAnswer,
    this.selectedIndex,
    this.isCorrect,
    this.onNext,
    this.showHint = true,
    this.autoAdvanceCorrect = false,
  });

  @override
  ConsumerState<_QuizQuestionView> createState() => _QuizQuestionViewState();
}

class _QuizQuestionViewState extends ConsumerState<_QuizQuestionView>
    with WidgetsBindingObserver {
  int _hintLevel = 0;
  bool _reviewedSentence = false;
  bool _isSubmitting = false;
  bool _isContinuing = false;
  Timer? _autoAdvanceTimer;
  int _autoAdvanceGeneration = 0;

  /// 「例文を確認」導線の位置特定用（初回コーチマーク表示に使用）。
  final GlobalKey _checkSentenceKey = GlobalKey();

  /// 「例文を復習する」導線の位置特定用（まとめクイズ側）。
  final GlobalKey _reviewSentenceKey = GlobalKey();

  /// このビューがコーチマークを出したか（破棄時に閉じるため）。
  bool _showedReviewCoach = false;

  bool get _hasResult =>
      widget.selectedIndex != null && widget.isCorrect != null;

  bool get _canAutoAdvance =>
      _hasResult &&
      widget.isCorrect == true &&
      widget.autoAdvanceCorrect &&
      widget.questionIndex + 1 < widget.totalQuestions &&
      widget.onNext != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scheduleAutoAdvanceIfNeeded();
    unawaited(_maybeShowReviewCoach());
  }

  /// 出題中に「例文へ戻って確認できる」ことを初回だけ案内する。
  /// 例文へ戻る導線が実際に出ている問題でのみ、1回限り。
  Future<void> _maybeShowReviewCoach() async {
    if (_hasResult) return;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(AppConfig.prefKeyQuizReviewCoachShown) ?? false) return;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || _hasResult) return;
      // 確認クイズは「例文を確認」、まとめクイズは「例文を復習する」が出る。
      final targetKey = _checkSentenceKey.currentContext != null
          ? _checkSentenceKey
          : (_reviewSentenceKey.currentContext != null
              ? _reviewSentenceKey
              : null);
      if (targetKey == null || ModalRoute.of(context)?.isCurrent != true) {
        return;
      }
      // 選択肢が多いと導線は画面外にある。先に見せてから強調する。
      await Scrollable.ensureVisible(
        targetKey.currentContext!,
        alignment: 0.8,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
      if (!mounted || _hasResult || ModalRoute.of(context)?.isCurrent != true) {
        return;
      }
      final shown = CoachMarkOverlay.show(
        context,
        targetKey: targetKey,
        id: 'quiz_review',
        analytics: ref.read(analyticsServiceProvider),
        // 押すと解答中に例文へ移る。そのまま解きたい人を止めない。
        skippable: true,
        icon: Icons.menu_book_outlined,
        title: L10n.of(context).coachQuizReviewTitle,
        message: L10n.of(context).coachQuizReviewMessage,
      );
      if (!shown) return;
      _showedReviewCoach = true;
      unawaited(prefs.setBool(AppConfig.prefKeyQuizReviewCoachShown, true));
    });
  }

  @override
  void didUpdateWidget(_QuizQuestionView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.questionIndex != widget.questionIndex) {
      _hintLevel = 0;
      _reviewedSentence = false;
      _isSubmitting = false;
      _isContinuing = false;
    }
    final resultChanged = oldWidget.questionIndex != widget.questionIndex ||
        oldWidget.selectedIndex != widget.selectedIndex ||
        oldWidget.isCorrect != widget.isCorrect;
    if (resultChanged) {
      _scheduleAutoAdvanceIfNeeded();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _cancelAutoAdvance();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cancelAutoAdvance();
    // 次の問題へ進むとこのビューだけ破棄される。対象を失ったコーチマークが
    // 残らないよう、自分が出したものはここで閉じる。
    if (_showedReviewCoach) {
      CoachMarkOverlay.dismissFor(_checkSentenceKey);
      CoachMarkOverlay.dismissFor(_reviewSentenceKey);
    }
    super.dispose();
  }

  void _scheduleAutoAdvanceIfNeeded() {
    _cancelAutoAdvance();
    if (!_canAutoAdvance) return;

    final generation = ++_autoAdvanceGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _autoAdvanceGeneration) return;
      if (MediaQuery.of(context).accessibleNavigation) return;
      _autoAdvanceTimer = Timer(
        _correctAnswerAutoAdvanceDelay,
        () => unawaited(_continueToNext()),
      );
    });
  }

  void _cancelAutoAdvance() {
    _autoAdvanceGeneration++;
    _autoAdvanceTimer?.cancel();
    _autoAdvanceTimer = null;
  }

  Future<void> _submitAnswer(int choiceIndex) async {
    final onAnswer = widget.onAnswer;
    if (_isSubmitting || _hasResult || onAnswer == null) return;

    setState(() => _isSubmitting = true);
    try {
      await onAnswer(choiceIndex, _hintLevel, _reviewedSentence);
    } finally {
      if (mounted && !_hasResult) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<void> _continueToNext() async {
    final onNext = widget.onNext;
    if (_isContinuing || !_hasResult || onNext == null) return;

    _cancelAutoAdvance();
    setState(() => _isContinuing = true);
    try {
      await onNext();
    } finally {
      if (mounted && _hasResult) {
        setState(() => _isContinuing = false);
      }
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

  Widget _buildInlineFeedback(BuildContext context) {
    final l10n = L10n.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final isCorrect = widget.isCorrect!;
    final feedbackColor =
        isCorrect ? colorScheme.primaryContainer : colorScheme.errorContainer;
    final feedbackForeground = isCorrect
        ? colorScheme.onPrimaryContainer
        : colorScheme.onErrorContainer;
    final accentColor = isCorrect ? colorScheme.primary : colorScheme.error;
    final meaning = widget.question.correctAnswerMeaning.trim();
    final pronunciation = widget.question.pronunciation.trim();
    final answerDetails = [
      widget.question.correctAnswer,
      if (meaning.isNotEmpty)
        meaning
      else if (pronunciation.isNotEmpty)
        pronunciation,
    ].join(' · ');
    final resultLabel = isCorrect ? l10n.quizCorrect : l10n.quizIncorrect;
    final nextLabel = widget.questionIndex + 1 >= widget.totalQuestions
        ? l10n.quizSeeResults
        : l10n.quizNextQuestion;
    return SafeArea(
      key: const ValueKey('quiz_inline_feedback'),
      top: false,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: feedbackColor,
          border: Border(top: BorderSide(color: accentColor, width: 2)),
        ),
        padding: const EdgeInsets.fromLTRB(
          AppConfig.defaultPadding,
          12,
          AppConfig.defaultPadding,
          12,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              container: true,
              liveRegion: true,
              label: '$resultLabel $answerDetails',
              child: ExcludeSemantics(
                child: Row(
                  children: [
                    Icon(
                      isCorrect ? Icons.check_circle : Icons.cancel,
                      color: accentColor,
                      size: 28,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            resultLabel,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  color: accentColor,
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            answerDetails,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                Theme.of(context).textTheme.bodyLarge?.copyWith(
                                      color: feedbackForeground,
                                      fontWeight: FontWeight.w600,
                                    ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            FilledButton(
              key: const ValueKey('quiz_next_button'),
              onPressed: _isContinuing ? null : _continueToNext,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              child: _isContinuing
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(nextLabel),
            ),
          ],
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

    return Listener(
      onPointerDown: (_) {
        if (_autoAdvanceTimer != null) _cancelAutoAdvance();
      },
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppConfig.defaultPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.totalQuestions > 1) ...[
                    // 進捗
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            L10n.of(context).quizProgress(
                              widget.questionIndex + 1,
                              widget.totalQuestions,
                            ),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 100,
                          child: LinearProgressIndicator(
                            value: (widget.questionIndex + 1) /
                                widget.totalQuestions,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                  ] else ...[
                    Text(
                      L10n.of(context).quizPrompt,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                  ],
                  // 穴埋め例文
                  Card(
                    child: Padding(
                      padding:
                          const EdgeInsets.all(AppConfig.defaultPadding * 1.5),
                      child: Text(
                        question.blankText,
                        style: Theme.of(context)
                            .textTheme
                            .headlineMedium
                            ?.copyWith(
                                fontWeight: FontWeight.w500,
                                height: 1.5,
                                fontSize: 28),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                  // ヒント1: ローマ字読み（問題文の下、正解部分を空欄に）
                  if (_hintLevel >= 1 && hasPronunciation) ...[
                    const SizedBox(height: 8),
                    Builder(builder: (context) {
                      final blanked = question
                              .blankSentencePronunciation.isNotEmpty
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
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
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
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 16),
                  // 4択
                  ...List.generate(question.choices.length, (i) {
                    final colorScheme = Theme.of(context).colorScheme;
                    final choicePronunciation =
                        i < question.choicePronunciations.length
                            ? question.choicePronunciations[i]
                            : '';
                    final showChoicePronunciation =
                        _hintLevel >= 1 && choicePronunciation.isNotEmpty;
                    final isSelected = _hasResult && widget.selectedIndex == i;
                    final isCorrectChoice = _hasResult &&
                        question.choices[i] == question.correctAnswer;
                    final isWrongSelection =
                        isSelected && widget.isCorrect == false;

                    Color? resultBackground;
                    Color? resultForeground;
                    BorderSide? resultSide;
                    IconData? resultIcon;
                    if (isCorrectChoice) {
                      resultBackground = colorScheme.primaryContainer;
                      resultForeground = colorScheme.onPrimaryContainer;
                      resultSide =
                          BorderSide(color: colorScheme.primary, width: 2);
                      resultIcon = Icons.check_circle;
                    } else if (isWrongSelection) {
                      resultBackground = colorScheme.errorContainer;
                      resultForeground = colorScheme.onErrorContainer;
                      resultSide =
                          BorderSide(color: colorScheme.error, width: 2);
                      resultIcon = Icons.cancel;
                    }

                    final answerLocked = _isSubmitting || _hasResult;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: showChoicePronunciation ? 84 : 56,
                        ),
                        child: ElevatedButton(
                          key: ValueKey('quiz_choice_$i'),
                          onPressed:
                              answerLocked ? null : () => _submitAnswer(i),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: resultBackground,
                            foregroundColor: resultForeground,
                            disabledBackgroundColor: resultBackground ??
                                colorScheme.surfaceContainerHighest,
                            disabledForegroundColor: resultForeground ??
                                colorScheme.onSurfaceVariant,
                            side: resultSide,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                  AppConfig.cardBorderRadius),
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      question.choices[i],
                                      style: const TextStyle(fontSize: 24),
                                      textAlign: TextAlign.center,
                                    ),
                                    if (showChoicePronunciation) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        choicePronunciation,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              fontStyle: FontStyle.italic,
                                              color: resultForeground ??
                                                  colorScheme.primary
                                                      .withValues(alpha: 0.75),
                                            ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              if (resultIcon != null) ...[
                                const SizedBox(width: 8),
                                Icon(
                                  resultIcon,
                                  color: isWrongSelection
                                      ? colorScheme.error
                                      : colorScheme.primary,
                                  semanticLabel: isWrongSelection
                                      ? L10n.of(context).quizIncorrect
                                      : L10n.of(context).quizCorrect,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                  if (!_hasResult && canReviewSentence) ...[
                    const SizedBox(height: 4),
                    TextButton(
                      key: _reviewSentenceKey,
                      onPressed: () => _showSentenceDetail(sentenceDetail),
                      child: Text(
                        _reviewedSentence
                            ? L10n.of(context).quizSentenceReviewed
                            : L10n.of(context).quizReviewSentence,
                        style: TextStyle(
                          fontSize: 15,
                          color: Theme.of(context).colorScheme.outline,
                        ),
                      ),
                    ),
                  ] else if (!_hasResult &&
                      widget.showHint &&
                      _hintLevel < maxHintLevel) ...[
                    const SizedBox(height: 4),
                    FilledButton.tonalIcon(
                      onPressed: () =>
                          setState(() => _hintLevel = maxHintLevel),
                      icon: const Icon(Icons.lightbulb_outline),
                      label: Text(L10n.of(context).quizHint),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ],
                  if (!_hasResult && widget.onShowSentence != null) ...[
                    const SizedBox(height: 4),
                    FilledButton.tonalIcon(
                      key: _checkSentenceKey,
                      onPressed: widget.onShowSentence,
                      icon: const Icon(Icons.menu_book_outlined),
                      label: Text(L10n.of(context).quizCheckSentence),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (_hasResult) _buildInlineFeedback(context),
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
  final bool showCorrectAnswerLabel;

  const _QuizAnswerWordRow({
    required this.question,
    required this.analyticsSource,
    this.showSentenceContext = true,
    this.showCorrectAnswerLabel = false,
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
                tooltip: L10n.of(context).quizPlaySentence,
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
                showCorrectAnswerLabel
                    ? L10n.of(context).quizCorrectAnswer(
                        question.correctAnswer,
                      )
                    : question.correctAnswer,
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
              tooltip: L10n.of(context).quizPlayWord,
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
                label: L10n.of(context).quizWhyCorrect,
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
                label: L10n.of(context).quizWhyIncorrect,
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
                Expanded(
                  child: Text(
                    L10n.of(context)
                        .quizProgress(questionIndex + 1, totalQuestions),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                const SizedBox(width: 12),
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
                    isCorrect
                        ? L10n.of(context).quizCorrect
                        : L10n.of(context).quizIncorrect,
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
                  showCorrectAnswerLabel: showExplanations && !isCorrect,
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
              key: const ValueKey('quiz_result_next_button'),
              onPressed: onNext,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: Text(
                questionIndex + 1 >= totalQuestions
                    ? L10n.of(context).quizSeeResults
                    : L10n.of(context).quizNextQuestion,
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
                  isCorrect
                      ? L10n.of(context).quizCorrect
                      : L10n.of(context).quizIncorrect,
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
