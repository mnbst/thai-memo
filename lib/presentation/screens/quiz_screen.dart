import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/config/app_config.dart';
import '../../core/quota_error.dart';
import '../../core/theme/app_colors.dart';
import '../../l10n/app_localizations.dart';
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
import '../widgets/coach_bullet_text.dart';
import '../widgets/topic_picker.dart';
import 'detail_screen.dart';
import 'paywall_screen.dart';

const String _summaryQuizVocabBeforeKey = 'summary_quiz_vocab_before';
const int _maxSummaryQuizVocabIncrease = 50;
const Duration _correctAnswerAutoAdvanceDelay = Duration(milliseconds: 1200);


/// 出題中の位置。1問だけのクイズには進み具合が無いので持たせない。
typedef QuizProgress = ({int index, int total});

QuizProgress? quizProgressOf(QuizState state) {
  if (state is QuizAnswering && state.questions.length > 1) {
    return (index: state.index, total: state.questions.length);
  }
  if (state is QuizShowResult && state.questions.length > 1) {
    return (index: state.index, total: state.questions.length);
  }
  return null;
}

/// AppBar に出す「2 / 5」。クイズの AppBar は画面ごとに別の場所が持つので、
/// 数え方だけをここに置いて共有する。
class QuizProgressCounter extends ConsumerWidget {
  const QuizProgressCounter({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = quizProgressOf(ref.watch(quizControllerProvider));
    if (progress == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(right: AppConfig.screenPadding),
      child: Center(
        child: Text(
          '${progress.index + 1} / ${progress.total}',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ),
    );
  }
}

/// 画面下端の固定バー。押せる導線だけを載せ、紙面とは細い罫で分ける。
class _QuizActionBar extends StatelessWidget {
  final List<Widget> children;

  const _QuizActionBar({required this.children});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.surface,
          border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
        ),
        padding: const EdgeInsets.fromLTRB(
            AppConfig.screenPadding, 12, AppConfig.screenPadding, 12),
        child: Row(children: children),
      ),
    );
  }
}

/// 空欄を金の下線に置き換えた例文。
///
/// 下線記号（`___`）そのものは透明にして線だけを引く。記号を出したままだと、
/// 途切れた線がタイ文字の一部に見える。
TextSpan buildQuizBlankSpan(String blankText, TextStyle base) {
  const marker = '___';
  final index = blankText.indexOf(marker);
  if (index < 0) return TextSpan(text: blankText, style: base);
  return TextSpan(
    style: base,
    children: [
      TextSpan(text: blankText.substring(0, index)),
      TextSpan(
        text: marker,
        style: base.copyWith(
          color: Colors.transparent,
          letterSpacing: 3,
          decoration: TextDecoration.underline,
          decorationColor: AppColors.gold,
          decorationThickness: 2.5,
        ),
      ),
      TextSpan(text: blankText.substring(index + marker.length)),
    ],
  );
}

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
/// 結果画面の演出のうち、案内を待たせる割合。1.0 だと終わり際の静かな動きまで
/// 待つことになり、案内が遅く感じる。
const double _resultAnimationWaitRatio = 0.6;

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
          unawaited(_runSummaryCoaches());
        }
      }
      // 結果画面を離れたら、そこに出していた案内は畳む。この State は
      // まとめクイズへ移っても作り直されないので、dispose では間に合わない
      // （対象を失った吹き出しが次の問題の上に残る）。
      if (prev is QuizSummary && next is! QuizSummary) {
        CoachMarkOverlay.dismissFor(_optionalChallengeKey);
        CoachMarkOverlay.dismissFor(_nextTopicKey);
            _abortSummaryCoachWait?.call();
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

  /// 結果画面の演出が落ち着くまで待つ。演出中に案内を重ねると、紙吹雪や
  /// 加算アニメーションに隠れて何を勧められたのか残らない。
  /// クラッカーと語彙スコアは同時に始まるので、長い方だけ待てばよい。
  ///
  /// 終わり際は動きが小さく、最後まで待つと案内が遅れて感じる。目立つ間だけ
  /// ([_resultAnimationWaitRatio]) 譲る。
  Future<void> _waitForResultAnimations() async {
    final celebration = _celebrationController.isAnimating
        ? _celebrationDuration * (1 - _celebrationController.value)
        : Duration.zero;
    final vocab = widget.showVocabScoreTransition
        ? _vocabTransitionDuration
        : Duration.zero;
    final wait =
        (celebration > vocab ? celebration : vocab) * _resultAnimationWaitRatio;
    if (wait > Duration.zero) await Future<void>.delayed(wait);
  }

  /// 結果画面の案内を順番に出す。
  ///
  /// 同時に出すと吹き出しが重なり、後から出したものが表示すらされないまま
  /// 「表示済み」になる。
  Future<void> _runSummaryCoaches() async {
    final challengeAction = await _maybeShowChallengeCoach();
    if (!mounted) return;
    // まとめクイズへ移る回は、ここで打ち切る。案内は対象を押した瞬間
    // （指を離す前）に閉じるので、続けると画面が切り替わる前の一瞬に
    // 次の吹き出しが出て、切り替わりと同時に消える。
    if (challengeAction == 'tapped') return;
    // 締めくくり → テーマ の順に出す。「間違えた例文はまた出る」を読んでから
    // 「次のテーマを選べる」を見せる方が、次の例文の話として続けて読める。
    final finished = await _maybeShowTourFinishCoach();
    if (!mounted) return;
    await _maybeShowNextTopicCoach(advancesAfterConfirm: finished);
    if (!mounted) return;
    // 次の例文へ進むのは案内をすべて読んだ後。テーマの案内より先に進めると、
    // 画面が切り替わって対象のチップごと消える。
    if (finished) await _advanceToNextSentenceAfterTourFinish();
  }

  /// 待っている案内を打ち切る手。画面を離れたときに呼ぶ。
  /// これが無いと、閉じられないまま連鎖が待ちっぱなしになる。
  VoidCallback? _abortSummaryCoachWait;

  /// 機能紹介の締めくくり。1回限り。
  ///
  /// ここまでで一通りの機能に触れている。あとは続けるだけだと伝える。
  ///
  /// ここだけはスポットライトを使わない。指す対象が無い話（画面の一部では
  /// なく全体の締め）なので、中央のダイアログで出す。
  ///
  /// 出せなかった回は表示済みにしない。ここで記録してしまうと、一度も
  /// 読まれないまま二度と出なくなる（結果画面はまた来るので次に回す）。
  ///
  /// 出して読まれたら true。呼び出し側は、続きの案内を出し終えてから
  /// 次の例文へ進める。
  Future<bool> _maybeShowTourFinishCoach() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(AppConfig.prefKeyTourFinishCoachShown) ?? false) {
      return false;
    }
    if (!mounted || ref.read(quizControllerProvider) is! QuizSummary) {
      _logFinishCoachSkip('not_summary');
      return false;
    }

    await _waitForResultAnimations();
    // 押した指を離す前に前の案内が閉じるので、画面の切り替えはこの後に
    // 始まる。一拍おいてから、まだ結果画面にいるかを確かめる。
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (!mounted) return false;
    if (ref.read(quizControllerProvider) is! QuizSummary) {
      _logFinishCoachSkip('left_summary');
      return false;
    }
    if (ModalRoute.of(context)?.isCurrent != true) {
      _logFinishCoachSkip('not_current');
      return false;
    }
    if (CoachMarkOverlay.isVisible) {
      _logFinishCoachSkip('overlay_busy');
      return false;
    }

    await prefs.setBool(AppConfig.prefKeyTourFinishCoachShown, true);
    // 読み終えたら例文画面へ自動で進む。着いた先で学習の流れを案内するので、
    // ここで予約しておく（クイズ結果の上では出せない）。
    await prefs.setBool(AppConfig.prefKeyLearningFlowCoachPending, true);
    if (!mounted) return false;
    final analytics = ref.read(analyticsServiceProvider);
    unawaited(analytics.logCoachMark(id: 'tour_finish', action: 'shown'));
    final seePremium = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const _TourFinishDialog(),
    );
    unawaited(analytics.logCoachMark(id: 'tour_finish', action: 'confirmed'));
    if (seePremium == true && mounted) {
      await PaywallBottomSheet.show(context, source: 'tour_finish');
    }
    return true;
  }

  /// 案内を読み終えたら、そのまま次の例文へ進める。
  ///
  /// 案内が「次の例文へ」を押させる文面ではなくなったので、押させずにこちらで
  /// 進める。生成はここから始まり、例文画面が待っている間に走る。
  ///
  /// 進めるのは結果画面から動いていない回だけ。読んでいる間に自分で次へ
  /// 進んだ人を、もう一度生成させて追い越さない。
  Future<void> _advanceToNextSentenceAfterTourFinish() async {
    final next = widget.onNextSentence;
    if (next == null) return;
    if (ref.read(quizControllerProvider) is! QuizSummary) return;
    if (ModalRoute.of(context)?.isCurrent != true) return;
    unawaited(_clearVocabBeforeQuiz());
    await next();
  }

  /// 締めくくりを出せなかった理由。出ないときに原因を追えるようにする。
  void _logFinishCoachSkip(String reason) {
    if (kDebugMode) debugPrint('coach: tour_finish skipped ($reason)');
  }

  /// まとめクイズ誘導ボタンを初回だけスポットライトで案内する。
  /// 確認クイズのサマリーで誘導ボタンが出る場合のみ、1回限り。
  /// 閉じ方（対象を押したか）を返す。
  Future<String?> _maybeShowChallengeCoach() async {
    if (widget.onOptionalChallenge == null) return null;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(AppConfig.prefKeyQuizButtonCoachShown) ?? false) {
      return null;
    }

    await _waitForResultAnimations();
    if (!mounted) return null;

    final completer = Completer<String?>();
    _abortSummaryCoachWait = () {
      if (!completer.isCompleted) completer.complete(null);
    };
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          ref.read(quizControllerProvider) is! QuizSummary ||
          _optionalChallengeKey.currentContext == null) {
        if (!completer.isCompleted) completer.complete(null);
        return;
      }
      unawaited(prefs.setBool(AppConfig.prefKeyQuizButtonCoachShown, true));
      final shown = CoachMarkOverlay.show(
        context,
        targetKey: _optionalChallengeKey,
        id: 'summary_quiz',
        analytics: ref.read(analyticsServiceProvider),
        // まとめクイズは普段は見送れる。ただしこの案内は1回限りなので、
        // ここでスキップを許すと、どんなものか一度も知らないまま
        // 二度と案内されない人が出る。初回だけは押させる。
        skippable: false,
        barrierDismissible: false,
        icon: Icons.emoji_events,
        title: L10n.of(context).coachSummaryQuizTitle,
        message: L10n.of(context).coachSummaryQuizMessage,
        emphasis: L10n.of(context).coachSummaryQuizEmphasis,
        onDismiss: (action) {
          if (!completer.isCompleted) completer.complete(action);
        },
      );
      if (!shown && !completer.isCompleted) completer.complete(null);
    });
    return completer.future;
  }

  /// 結果画面の「次のテーマ」変更チップを初回だけスポットライトで案内する。
  /// チップが表示される（＝次の例文へ進める）場合のみ、1回限り。
  /// 誘導ボタンがある確認クイズのサマリーではコーチが重ならないよう譲る。
  ///
  /// [advancesAfterConfirm] が true の回は、閉じた後に次の例文へ進む。
  /// ボタンの文言をその行き先に合わせる。
  Future<void> _maybeShowNextTopicCoach({
    required bool advancesAfterConfirm,
  }) async {
    if (widget.onNextSentence == null) return;
    if (widget.onOptionalChallenge != null) return;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(AppConfig.prefKeyNextTopicCoachShown) ?? false) return;

    await _waitForResultAnimations();
    if (!mounted) return;

    final completer = Completer<void>();
    _abortSummaryCoachWait = () {
      if (!completer.isCompleted) completer.complete();
    };
    // サマリー画面が描画され、チップの位置が確定してから表示する。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          ref.read(quizControllerProvider) is! QuizSummary ||
          _nextTopicKey.currentContext == null) {
        if (!completer.isCompleted) completer.complete();
        return;
      }
      // 表示時にフラグを立てる。ボタン／チップタップのどちらで閉じても再表示しない。
      unawaited(prefs.setBool(AppConfig.prefKeyNextTopicCoachShown, true));
      final shown = CoachMarkOverlay.show(
        context,
        targetKey: _nextTopicKey,
        id: 'next_topic',
        analytics: ref.read(analyticsServiceProvider),
        icon: Icons.palette_outlined,
        title: L10n.of(context).coachTopicTitle,
        message: L10n.of(context).coachTopicMessage,
        // テーマを変えるかどうかは本人が決める。ここは在り処を教えるだけ。
        targetTappable: false,
        confirmLabel: advancesAfterConfirm
            ? L10n.of(context).coachTopicNext
            : L10n.of(context).coachGotIt,
        onDismiss: (_) {
          if (!completer.isCompleted) completer.complete();
        },
      );
      if (!shown && !completer.isCompleted) completer.complete();
    });
    await completer.future;
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
    _abortSummaryCoachWait?.call();
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

    final progress = quizProgressOf(quizState);
    // 進み具合は画面の上端に細い帯で置く。本文に混ぜると、読むべき例文より
    // 先に目に入る。
    final body = Column(
      children: [
        if (progress != null)
          LinearProgressIndicator(
            value: (progress.index + 1) / progress.total,
            minHeight: 4,
            backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
            color: AppColors.gold,
          ),
        Expanded(child: _buildContent(context, quizState)),
      ],
    );

    if (!widget.showAppBar) {
      return body;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title ?? L10n.of(context).quizTodayTitle),
        actions: const [QuizProgressCounter()],
      ),
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
    return LoadingCard(message: L10n.of(context).quizGenerating);
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
      showHints: widget.learningSentence == null,
      onShowSentence: widget.onBackToLearningStart,
      onAnswer: (choiceIndex, hintLevel, reviewedSentence) async {
        await ref.read(quizControllerProvider.notifier).answerQuestion(
              choiceIndex,
              hintLevel: hintLevel,
              reviewedSentence: reviewedSentence,
            );
      },
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
      showHints: widget.learningSentence == null,
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

  /// ヒント（発音→訳文の2段階）を出すか。
  ///
  /// 5問テストだけ true。例文を読んだ直後に解く確認クイズにヒントは要らない
  /// （あちらは例文へ戻れば済む）。
  final bool showHints;
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
    this.showHints = true,
    this.autoAdvanceCorrect = false,
  });

  @override
  ConsumerState<_QuizQuestionView> createState() => _QuizQuestionViewState();
}

class _QuizQuestionViewState extends ConsumerState<_QuizQuestionView>
    with WidgetsBindingObserver {
  /// 開いたヒントの段（0=未使用 / 1=発音 / 2=訳文）。回答と一緒に送り、
  /// サーバー側のUVMがαの重みに使う。
  int _hintLevel = 0;
  bool _reviewedSentence = false;
  bool _isSubmitting = false;
  bool _isContinuing = false;
  Timer? _autoAdvanceTimer;
  int _autoAdvanceGeneration = 0;

  /// 「例文を確認」導線の位置特定用（初回コーチマーク表示に使用）。
  final GlobalKey _checkSentenceKey = GlobalKey();

  /// 出題中の案内で光らせる範囲。問題文から「例文を確認」までをひとまとまりで
  /// 見せる。導線だけ光らせても、何をする画面なのかは伝わらない。
  final GlobalKey _quizBodyKey = GlobalKey();

  /// ヒント導線の位置特定用（初回コーチマーク表示に使用）。
  final GlobalKey _hintKey = GlobalKey();

  /// 「例文を復習する」導線の位置特定用（まとめクイズ側）。
  final GlobalKey _reviewSentenceKey = GlobalKey();

  /// このビューがコーチマークを出したか（破棄時に閉じるため）。
  bool _showedReviewCoach = false;

  bool get _hasResult =>
      widget.selectedIndex != null && widget.isCorrect != null;

  bool get _canAutoAdvance =>
      _hasResult &&
      widget.isCorrect == true &&
      // 解説を出す回は自分で読み終えてから進む。1.2秒で流すなら出す意味がない。
      widget.question.explanation.trim().isEmpty &&
      widget.autoAdvanceCorrect &&
      widget.questionIndex + 1 < widget.totalQuestions &&
      widget.onNext != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scheduleAutoAdvanceIfNeeded();
    unawaited(_maybeShowReviewCoach());
    unawaited(_maybeShowHintCoach());
  }

  /// ヒントが2段階あることを初回だけ案内する。
  ///
  /// ヒント導線が出ている5問クイズでのみ、まだ一度もヒントを開いていない
  /// 問題で1回限り。他のコーチマークと重なる回は出さず、フラグも立てない
  /// （次の問題で出し直す）。
  Future<void> _maybeShowHintCoach() async {
    if (_hasResult || !widget.showHints) return;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(AppConfig.prefKeyQuizHintCoachShown) ?? false) return;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || _hasResult || _hintLevel > 0) return;
      if (CoachMarkOverlay.isVisible) return;
      if (_hintKey.currentContext == null ||
          ModalRoute.of(context)?.isCurrent != true) {
        return;
      }
      // 選択肢が多いとヒントは画面外にある。先に見せてから強調する。
      await Scrollable.ensureVisible(
        _hintKey.currentContext!,
        alignment: 0.8,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
      if (!mounted ||
          _hasResult ||
          _hintLevel > 0 ||
          CoachMarkOverlay.isVisible ||
          ModalRoute.of(context)?.isCurrent != true) {
        return;
      }
      final shown = CoachMarkOverlay.show(
        context,
        targetKey: _hintKey,
        id: 'quiz_hint',
        analytics: ref.read(analyticsServiceProvider),
        icon: Icons.lightbulb_outline,
        title: L10n.of(context).coachQuizHintTitle,
        message: L10n.of(context).coachQuizHintMessage,
        // ヒントを使うかは解いている本人が決める。案内から押させない。
        targetTappable: false,
        confirmLabel: L10n.of(context).coachGotIt,
      );
      if (!shown) return;
      unawaited(prefs.setBool(AppConfig.prefKeyQuizHintCoachShown, true));
    });
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
        // 光らせるのは問題文から導線までのひとまとまり。
        targetKey: _quizBodyKey,
        id: 'quiz_review',
        analytics: ref.read(analyticsServiceProvider),
        icon: Icons.menu_book_outlined,
        title: L10n.of(context).coachQuizReviewTitle,
        message: L10n.of(context).coachQuizReviewMessage,
        // 解答中なので押させない。ここは「いつでも戻れる」と知らせるだけで、
        // 実際に戻るかどうかは解いている本人が決める。
        targetTappable: false,
        confirmLabel: L10n.of(context).coachGotIt,
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
      CoachMarkOverlay.dismissFor(_quizBodyKey);
      CoachMarkOverlay.dismissFor(_checkSentenceKey);
      CoachMarkOverlay.dismissFor(_reviewSentenceKey);
    }
    // ヒントの案内は自分が出したものだけ閉じる（dismissFor が持ち主を見る）。
    CoachMarkOverlay.dismissFor(_hintKey);
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

  /// 正誤と正解語の要約。本文の流れの中に置く。
  ///
  /// 下端に貼り付けると、続く解説まで読み切れない。下端はボタンだけに残す。
  Widget _buildFeedbackBox(BuildContext context) {
    final l10n = L10n.of(context);
    final isCorrect = widget.isCorrect!;
    final accent = isCorrect ? AppColors.jade : AppColors.vermilion;
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
    // 読ませたいのは「なぜその語なのか」。解説が無い問題だけ、正解語と意味で
    // 埋め合わせる。
    final explanation = widget.question.explanation.trim();
    final body = explanation.isNotEmpty ? explanation : answerDetails;
    return Semantics(
      key: const ValueKey('quiz_inline_feedback'),
      container: true,
      liveRegion: true,
      label: '$resultLabel $answerDetails',
      child: ExcludeSemantics(
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppConfig.defaultPadding),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(AppConfig.cardBorderRadius),
            border: Border.all(color: accent.withValues(alpha: 0.35)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    isCorrect ? Icons.check_rounded : Icons.close_rounded,
                    size: 18,
                    color: accent,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    resultLabel,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: accent,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                body,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 下端の固定バー。左は例文へ戻る導線、右は先へ進む導線。
  Widget? _buildActionBar(BuildContext context) {
    final l10n = L10n.of(context);
    final showCheck = widget.onShowSentence != null;
    final showNext = _hasResult && widget.onNext != null;
    if (!showCheck && !showNext) return null;
    final nextLabel = widget.questionIndex + 1 >= widget.totalQuestions
        ? l10n.quizSeeResults
        : l10n.quizNextQuestion;
    return _QuizActionBar(
      children: [
        if (showCheck)
          Expanded(
            child: OutlinedButton(
              key: _checkSentenceKey,
              onPressed: widget.onShowSentence,
              child: Text(l10n.quizCheckSentence),
            ),
          ),
        if (showCheck && showNext) const SizedBox(width: 12),
        if (showNext)
          Expanded(
            child: FilledButton(
              key: const ValueKey('quiz_next_button'),
              onPressed: _isContinuing ? null : _continueToNext,
              child: _isContinuing
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(nextLabel),
            ),
          ),
      ],
    );
  }

  /// 穴埋め例文のカード。ヒントで開く発音と訳文もこの中に積む。
  Widget _buildSentenceCard(BuildContext context) {
    final theme = Theme.of(context);
    final question = widget.question;
    final hasPronunciation = question.sentencePronunciation.isNotEmpty;
    final hasTranslation = question.japaneseTranslation.isNotEmpty;
    // タイ文字の大きさは本文の見出し系より一段上げる。声調記号と母音記号が
    // 上下に付くので、日本語と同じ級数だと潰れて読めない。
    final base = (theme.textTheme.headlineMedium ?? const TextStyle()).copyWith(
      fontSize: 28,
      fontWeight: FontWeight.w500,
      height: 1.6,
    );
    final blankedPronunciation = question.blankSentencePronunciation.isNotEmpty
        ? question.blankSentencePronunciation
        : question.pronunciation.isNotEmpty
            ? question.sentencePronunciation
                .replaceFirst(question.pronunciation, '___')
            : '';
    final showPronunciation = widget.showHints &&
        _hintLevel >= 1 &&
        hasPronunciation &&
        blankedPronunciation.isNotEmpty &&
        blankedPronunciation != question.sentencePronunciation;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text.rich(buildQuizBlankSpan(question.blankText, base)),
            if (showPronunciation) ...[
              const SizedBox(height: 10),
              Text(
                blankedPronunciation,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontStyle: FontStyle.italic,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (widget.showHints && _hintLevel >= 2 && hasTranslation) ...[
              const SizedBox(height: 8),
              Text(
                question.japaneseTranslation,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 選択肢1つ。タイ語とローマ字読みを1行に並べ、右端に正誤を出す。
  Widget _buildChoiceTile(BuildContext context, int index) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final question = widget.question;
    final choicePronunciation = index < question.choicePronunciations.length
        ? question.choicePronunciations[index]
        : '';
    final showChoicePronunciation =
        widget.showHints && _hintLevel >= 1 && choicePronunciation.isNotEmpty;
    final isSelected = _hasResult && widget.selectedIndex == index;
    final isCorrectChoice =
        _hasResult && question.choices[index] == question.correctAnswer;
    final isWrongSelection = isSelected && widget.isCorrect == false;

    // 正誤は緑と朱で示す。深藍で塗ると「選んだ」ことしか伝わらず、
    // 合っていたのかが読み取れない。
    Color? accent;
    IconData? resultIcon;
    if (isCorrectChoice) {
      accent = AppColors.jade;
      resultIcon = Icons.check_rounded;
    } else if (isWrongSelection) {
      accent = AppColors.vermilion;
      resultIcon = Icons.close_rounded;
    }
    // 回答後、関わらなかった選択肢は沈める。同じ濃さで残ると、どれが答えか
    // 目が迷う。
    final isDimmed = _hasResult && accent == null;
    final foreground = accent ??
        (isDimmed
            ? colorScheme.onSurfaceVariant.withValues(alpha: 0.6)
            : colorScheme.onSurface);

    final answerLocked = _isSubmitting || _hasResult;
    return ElevatedButton(
      key: ValueKey('quiz_choice_$index'),
      onPressed: answerLocked ? null : () => _submitAnswer(index),
      style: ElevatedButton.styleFrom(
        // 未回答の選択肢は白い面＋罫線。塗り潰すと4つ並んだときに画面が
        // 重くなり、タイ文字も読みにくくなる。
        elevation: 0,
        alignment: Alignment.centerLeft,
        backgroundColor: accent?.withValues(alpha: 0.08) ?? colorScheme.surface,
        disabledBackgroundColor:
            accent?.withValues(alpha: 0.08) ?? colorScheme.surface,
        foregroundColor: foreground,
        disabledForegroundColor: foreground,
        side: BorderSide(
          color: accent ?? colorScheme.outlineVariant,
          width: accent != null ? 1.5 : 1,
        ),
        minimumSize: const Size.fromHeight(58),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConfig.cardBorderRadius),
        ),
      ),
      child: Row(
        children: [
          Flexible(
            child: Text(
              question.choices[index],
              // タイ文字は太字にすると声調記号と頭のループが潰れるので w500 まで。
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w500,
                color: foreground,
              ),
            ),
          ),
          if (showChoicePronunciation) ...[
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                choicePronunciation,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontStyle: FontStyle.italic,
                  color: colorScheme.onSurfaceVariant
                      .withValues(alpha: isDimmed ? 0.6 : 1),
                ),
              ),
            ),
          ],
          const Spacer(),
          if (resultIcon != null) ...[
            const SizedBox(width: 8),
            Icon(
              resultIcon,
              color: accent,
              semanticLabel: isWrongSelection
                  ? L10n.of(context).quizIncorrect
                  : L10n.of(context).quizCorrect,
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    final question = widget.question;
    // ヒントは 1=発音 / 2=訳文 の2段階。片方しか無い例文でも段階の意味は
    // 変えず、使える段階だけを順に開示する（UVMのα倍率が段階に対応する）。
    final availableHintLevels = <int>[
      if (question.sentencePronunciation.isNotEmpty) 1,
      if (question.japaneseTranslation.isNotEmpty) 2,
    ];
    final nextHintLevel = availableHintLevels.firstWhere(
      (level) => level > _hintLevel,
      orElse: () => 0,
    );
    final sentenceDetail = question.sentenceDetail;
    final canReviewSentence =
        widget.totalQuestions > 1 && sentenceDetail != null;
    final actionBar = _buildActionBar(context);

    return Listener(
      onPointerDown: (_) {
        if (_autoAdvanceTimer != null) _cancelAutoAdvance();
      },
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                  AppConfig.screenPadding, 16, AppConfig.screenPadding, 20),
              child: KeyedSubtree(
                key: _quizBodyKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      l10n.quizPrompt,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildSentenceCard(context),
                    const SizedBox(height: 16),
                    ...List.generate(
                      question.choices.length,
                      (i) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _buildChoiceTile(context, i),
                      ),
                    ),
                    if (_hasResult) ...[
                      const SizedBox(height: 4),
                      _buildFeedbackBox(context),
                    ],
                    if (!_hasResult &&
                        widget.showHints &&
                        availableHintLevels.isNotEmpty)
                      // 全段階を出し切ってもボタンは不活性のまま残す。消すと
                      // 4択の位置がずれ、使い切ったことも伝わらない。
                      KeyedSubtree(
                        key: _hintKey,
                        child: TextButton.icon(
                          key: const ValueKey('quiz_hint_button'),
                          onPressed: nextHintLevel == 0
                              ? null
                              : () =>
                                  setState(() => _hintLevel = nextHintLevel),
                          icon: const Icon(Icons.lightbulb_outline, size: 20),
                          label: Text(switch (nextHintLevel) {
                            1 => l10n.quizHintPronunciation,
                            2 => l10n.quizHintTranslation,
                            _ => l10n.quizHintShown,
                          }),
                        ),
                      ),
                    if (!_hasResult && canReviewSentence)
                      TextButton(
                        key: _reviewSentenceKey,
                        onPressed: () => _showSentenceDetail(sentenceDetail),
                        child: Text(
                          _reviewedSentence
                              ? l10n.quizSentenceReviewed
                              : l10n.quizReviewSentence,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          if (actionBar != null) actionBar,
        ],
      ),
    );
  }
}

/// 機能紹介の締めくくり。画面の一部ではなく全体の締めなので、スポットライト
/// ではなく中央のダイアログで出す。
///
/// 2ページに分ける。1ページ目は5問クイズの解き方（解き終えた直後なので、次に
/// 活かせる話として読める）、2ページ目は間違えた例文の扱い。1枚に詰めると
/// どちらも同じ重さで並んで、どちらも読まれない。
class _TourFinishDialog extends ConsumerStatefulWidget {
  const _TourFinishDialog();

  @override
  ConsumerState<_TourFinishDialog> createState() => _TourFinishDialogState();
}

class _TourFinishDialogState extends ConsumerState<_TourFinishDialog> {
  int _page = 0;

  static const _pageCount = 2;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    // すでにプレミアムの人に回数差とペイウォールを見せても意味がない。
    final isPremium = ref.watch(isPremiumProvider);
    final isLast = _page == _pageCount - 1;

    return AlertDialog(
      icon: Icon(
        _page == 0 ? Icons.emoji_events_outlined : Icons.autorenew,
        color: theme.colorScheme.primary,
        size: 32,
      ),
      title: Text(
        _page == 0 ? l10n.coachSummaryTipsTitle : l10n.coachTourFinishTitle,
      ),
      // ページを差し替えて出す。高さを決め打ちすると、短いページで下に
      // 大きな余白が残る。
      content: AnimatedSize(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        alignment: Alignment.topCenter,
        child: _page == 0
            ? CoachEmphasizedText(
                key: const ValueKey('tour_finish_page_0'),
                text: l10n.coachSummaryTipsBody,
                emphasis: l10n.coachSummaryTipsEmphasis,
                style: theme.textTheme.bodyMedium,
              )
            : _TourFinishRecapPage(
                key: const ValueKey('tour_finish_page_1'),
                isPremium: isPremium,
              ),
      ),
      // 端末の文字サイズを大きくしている場合でも溢れないようにする。
      scrollable: true,
      actions: [
        Row(
          children: [
            Text(
              l10n.coachStepLabel(_page + 1, _pageCount),
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const Spacer(),
            if (isLast && !isPremium)
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(l10n.coachTourFinishSeePremium),
              ),
            // ここは読み物なので閉じるだけ。次の例文へ進むのは、この後に出る
            // テーマの案内を読み終えてから。
            FilledButton(
              onPressed: () => isLast
                  ? Navigator.pop(context, false)
                  : setState(() => _page += 1),
              child: Text(isLast ? l10n.coachGotIt : l10n.coachNext),
            ),
          ],
        ),
      ],
    );
  }
}

/// 締めくくりの本文。間違えた例文の扱いと、1日に作れる本数。
class _TourFinishRecapPage extends StatelessWidget {
  const _TourFinishRecapPage({super.key, required this.isPremium});

  final bool isPremium;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    final baseStyle = theme.textTheme.bodyMedium;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CoachEmphasizedText(
          text: l10n.coachTourFinishMessage,
          emphasis: l10n.coachTourFinishEmphasis,
          style: baseStyle,
        ),
        if (!isPremium) ...[
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.bolt, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  l10n.coachTourFinishQuota(
                    freeDailySentences,
                    premiumDailySentences,
                  ),
                  style: baseStyle?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
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
    final l10n = L10n.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final accent = isCorrect ? AppColors.jade : AppColors.vermilion;

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
                AppConfig.screenPadding, 16, AppConfig.screenPadding, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 正誤。緑と朱で示し、面は薄く敷くだけにする。
                Container(
                  padding: const EdgeInsets.all(AppConfig.defaultPadding),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.08),
                    borderRadius:
                        BorderRadius.circular(AppConfig.cardBorderRadius),
                    border: Border.all(color: accent.withValues(alpha: 0.35)),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isCorrect ? Icons.check_rounded : Icons.close_rounded,
                        color: accent,
                        size: 22,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        isCorrect ? l10n.quizCorrect : l10n.quizIncorrect,
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: accent,
                                  fontWeight: FontWeight.w700,
                                ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // 正解ワード
                Card(
                  child: Padding(
                    padding:
                        const EdgeInsets.all(AppConfig.defaultPadding * 1.5),
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
                if (showExplanations &&
                    _hasQuizExplanationContent(question)) ...[
                  const SizedBox(height: 16),
                  _QuizExplanationSection(question: question),
                ],
                if (showExplanations) ...[
                  const SizedBox(height: 16),
                  // 4択（正誤ハイライト付き）
                  ...List.generate(question.choices.length, (i) {
                    final isSelected = i == selectedIndex;
                    final isCorrectChoice =
                        question.choices[i] == question.correctAnswer;
                    Color? choiceAccent;
                    if (isCorrectChoice) {
                      choiceAccent = AppColors.jade;
                    } else if (isSelected && !isCorrect) {
                      choiceAccent = AppColors.vermilion;
                    }
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Container(
                        constraints: const BoxConstraints(minHeight: 58),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 12),
                        decoration: BoxDecoration(
                          color: choiceAccent?.withValues(alpha: 0.08) ??
                              colorScheme.surface,
                          borderRadius:
                              BorderRadius.circular(AppConfig.cardBorderRadius),
                          border: Border.all(
                            color: choiceAccent ?? colorScheme.outlineVariant,
                            width: choiceAccent != null ? 1.5 : 1,
                          ),
                        ),
                        alignment: Alignment.centerLeft,
                        child: Text(
                          question.choices[i],
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w500,
                            color: choiceAccent ??
                                colorScheme.onSurfaceVariant
                                    .withValues(alpha: 0.6),
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              ],
            ),
          ),
        ),
        _QuizActionBar(
          children: [
            if (showExplanations)
              Expanded(
                child: FilledButton(
                  key: const ValueKey('quiz_result_next_button'),
                  onPressed: onNext,
                  child: Text(
                    questionIndex + 1 >= totalQuestions
                        ? l10n.quizSeeResults
                        : l10n.quizNextQuestion,
                  ),
                ),
              )
            else
              Expanded(
                child: FilledButton.icon(
                  key: const ValueKey('quiz_result_next_button'),
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
                ),
              ),
          ],
        ),
      ],
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
