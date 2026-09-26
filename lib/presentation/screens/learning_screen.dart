import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../l10n/app_localizations.dart';
import '../../data/models/thai_sentence.dart';
import '../providers/daily_set_provider.dart';
import '../providers/analytics_provider.dart';
import '../providers/sentence_provider.dart';
import '../providers/quiz_provider.dart';
import '../providers/settings_provider.dart';
import '../../services/learning_progress_store.dart';
import '../providers/review_prompt_provider.dart';
import 'quiz_screen.dart';
import 'today_screen.dart';

///
/// 進めてよいのは、いま表示している1本の確認クイズを解き終えたときだけ。
/// [answered] が null なのは、確認クイズを経ずにここへ来たとき（終了済みの
/// まとめクイズが再起動で復元され、その「次のセット」を押した場合など）で、
/// 進めると読んでいない1本と、その確認クイズが飛ぶ。
///
/// 解いた1本がカーソルと違うときも進めない。別端末が先へ進めていた場合で、
/// さらに advance すると間の1本を飛ばす。
///
/// セットを消化していないとき（自発生成・使い切り）は従来どおり進めてよい。
@visibleForTesting
bool shouldAdvanceDailySetCursor({
  required DailySetState set,
  required ThaiSentence? answered,
  LearningStage stage = LearningStage.sentence,
}) {
  if (!set.isActive) return true;
  // まとめクイズはセットの締め。最後の1本まで読み終えた位置で解いているので、
  // 確認クイズの持ち主が手元に残っていなくても進めてよい。まとめクイズを始める
  // ときの reset() で [answered] は落ちるため、ここを見ないと同じセットの
  // 最後の1本へ戻り、まとめクイズを何度も解かされる。
  if (stage == LearningStage.summaryQuiz && set.isLast) return true;
  return answered != null && set.current?.id == answered.id;
}

class LearningScreen extends ConsumerStatefulWidget {
  /// 初回の学習が一巡（まとめクイズ完了）した直後に呼ばれる。
  /// 通知の案内を出してよいタイミング（まとめクイズの結果／その見送り）。

  const LearningScreen({
    super.key,
    this.onReload,
  });

  /// 今日の例文を取り直す（配信の取り込みからやり直す）。
  final Future<void> Function()? onReload;

  @override
  ConsumerState<LearningScreen> createState() => LearningScreenState();
}

class LearningScreenState extends ConsumerState<LearningScreen> {
  LearningStage _stage = LearningStage.sentence;
  ThaiSentence? _quizSentence;

  @override
  void initState() {
    super.initState();
    ref.listenManual(quizControllerProvider, (previous, next) {
      if (next is QuizInitial && mounted) {
        setState(() {
          _stage = LearningStage.sentence;
          _quizSentence = null;
        });
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      restoreProgress();
      ref.listenManual(sentenceControllerProvider, (prev, next) {
        if (prev is SentenceStateLoading &&
            next is SentenceStateSuccess &&
            next.generated &&
            _stage == LearningStage.sentence) {
          ref.read(quizControllerProvider.notifier).prepareQuiz(next.sentence);
        }
      });
    });
  }

  /// 前回の続きから開く。
  ///
  /// 段はレコードの進み具合から導出する（まとめクイズの進行が残っていれば
  /// そこへ戻す）。保存された段を読むのではないので、段と中身が食い違わない。
  ///
  /// 起動時のほか、別端末の進み具合を取り込んだあとにも呼ばれる（例文を
  /// 読んでいる段にいるときだけ動く）。
  Future<void> restoreProgress() async {
    if (_stage != LearningStage.sentence) return;
    // カーソルの復元を待つ。レコードを読むのはその後でよい。
    await ref.read(dailySetProvider.notifier).restored;
    if (!mounted || _stage != LearningStage.sentence) return;

    final record = await ref.read(learningProgressStoreProvider).load();
    if (!mounted) return;

    // 「この1本の確認クイズは受けた」を引き継ぐ。これが無いと、再起動後の
    // 「次へ」が確認クイズを受けていない扱いになり、同じ1本に留まる。
    final answeredId = record.confirmationQuizSentenceId;
    if (answeredId != null) {
      _quizSentence = ref
          .read(dailySetProvider)
          .sentences
          .where((sentence) => sentence.id == answeredId)
          .firstOrNull;
    }

    if (record.stage != LearningStage.summaryQuiz) return;

    final restored = await ref
        .read(quizControllerProvider.notifier)
        .restoreSavedSummaryQuiz();
    if (!mounted || !restored) return;
    _setStage(LearningStage.summaryQuiz);
  }

  /// いま例文を読んでいる段か。クイズ中は本文を裏で差し替えない。
  bool get isOnSentenceStage => _stage == LearningStage.sentence;

  /// 段は画面の状態でしかない。保存するのは進み具合（レコード）のほうで、
  /// 段はそこから導出する。
  void _setStage(LearningStage newStage) {
    setState(() => _stage = newStage);
  }

  /// 確認クイズを受けた1本を覚える。再起動をまたいでカーソルを進められる
  /// ようにするため、画面の変数だけでなくレコードにも残す。
  void _rememberConfirmationQuiz(ThaiSentence sentence) {
    _quizSentence = sentence;
    final id = sentence.id;
    if (id == null) return;
    unawaited(
      ref.read(learningProgressStoreProvider).update(
            (record) => record.copyWith(confirmationQuizSentenceId: id),
          ),
    );
  }

  void _returnToLearningTop() {
    final sentence = _quizSentence;
    if (sentence != null) {
      ref.read(sentenceControllerProvider.notifier).showSentence(sentence);
    }
    _setStage(LearningStage.sentence);
  }

  void showSentenceStage() {
    _quizSentence = null;
    unawaited(
      ref
          .read(learningProgressStoreProvider)
          .update((record) => record.copyWith(clearConfirmation: true)),
    );
    ref.read(quizControllerProvider.notifier).reset();
    _setStage(LearningStage.sentence);
  }

  /// まとめクイズへ進む。セットの締めなので、ここは飛ばせない導線にする。
  Future<void> _startSummaryQuiz() async {
    final quizNotifier = ref.read(quizControllerProvider.notifier);
    quizNotifier.reset();
    unawaited(
      quizNotifier.generateAndStartQuiz(),
    );
    _setStage(LearningStage.summaryQuiz);
  }

  /// 次の例文へ進む。
  ///
  /// 配信セットに残りがあれば、そこから出すだけで生成しない（クォータもLLMも
  /// 消費しない）。使い切ったら従来どおり生成へ落ちる。テーマの適用可否・
  /// トライアル消費は controller 側で判定する。
  Future<void> _proceedToNextSentence() async {
    final set = ref.read(dailySetProvider);
    final current = set.current;
    if (!shouldAdvanceDailySetCursor(
          set: set,
          answered: _quizSentence,
          stage: _stage,
        ) &&
        current != null) {
      // カーソルは動かさず、現在位置の1本を出すだけ。
      _setStage(LearningStage.sentence);
      ref.read(sentenceControllerProvider.notifier).showSentence(current);
      ref.read(quizControllerProvider.notifier).prepareQuiz(current);
      return;
    }

    final next = await ref.read(dailySetProvider.notifier).advance();
    if (next == null) {
      await _generateNextLearningSentence();
      return;
    }
    if (!mounted) return;
    _setStage(LearningStage.sentence);
    ref.read(sentenceControllerProvider.notifier).showSentence(next);
    ref.read(quizControllerProvider.notifier).prepareQuiz(next);
  }

  Future<void> _generateNextLearningSentence() async {
    _setStage(LearningStage.sentence);
    final genParams = ref.read(generationParamsProvider);
    await ref.read(sentenceControllerProvider.notifier).generateSentence(
          generationParams: genParams,
          count: learningSetSize,
        );
    final sentenceState = ref.read(sentenceControllerProvider);
    if (sentenceState is SentenceStateSuccess) {
      ref
          .read(quizControllerProvider.notifier)
          .prepareQuiz(sentenceState.sentence);
      ref.invalidate(allSentencesProvider);
      unawaited(_requestReviewAfterSentenceGenerated());
    }
  }

  /// 例文が出た直後は満足度が高い。クイズまで進まない層への唯一の依頼機会
  /// なので、生成の完了を待ってから静かに出す。
  Future<void> _requestReviewAfterSentenceGenerated() async {
    await Future<void>.delayed(const Duration(seconds: 2));
    if (!mounted ||
        ref.read(sentenceControllerProvider) is! SentenceStateSuccess) {
      return;
    }
    final outcome = await ref
        .read(reviewPromptServiceProvider)
        .maybeRequestAfterSentenceGenerated();
    unawaited(
      ref.read(analyticsServiceProvider).logReviewPrompt(
            source: 'sentence',
            outcome: outcome.name,
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    // この確認クイズのサマリーでまとめクイズへ誘導するか。
    // セットの最後の1本＝1サイクルの締め。本数を別に数えていた頃は、セットと
    // 数えた本数が食い違うと節目がずれた。
    final offerSummaryQuiz = ref.watch(dailySetProvider).isLast;

    return switch (_stage) {
      LearningStage.sentence => TodayScreen(
          onReload: widget.onReload,
          onStartQuiz: (sentence, offerSource) {
            _rememberConfirmationQuiz(sentence);
            final quizNotifier = ref.read(quizControllerProvider.notifier);
            final quizState = ref.read(quizControllerProvider);

            // 既に回答中/結果表示中ならそのまま再表示
            if (quizState is QuizAnswering || quizState is QuizShowResult) {
              // nothing
            } else {
              quizNotifier.startLearningQuiz(
                sentence,
                offerSource: offerSource,
              );
            }
            _setStage(LearningStage.confirmationQuiz);
          },
        ),
      LearningStage.confirmationQuiz => Scaffold(
          appBar: AppBar(
            title: Text(l10n.navLearn),
            automaticallyImplyLeading: false,
            actions: const [QuizProgressCounter()],
          ),
          body: QuizScreen(
            showAppBar: false,
            title: l10n.learnQuizTitle,
            learningSentence: _quizSentence,
            onBackToLearningStart: _returnToLearningTop,
            // セットを消化しきったら、次は必ずまとめクイズ。以前は「挑戦する」
            // という任意の導線で、通り過ぎると節目が来ないまま本数だけ伸びた。
            // 5本＝1サイクルにした以上、締めを飛ばせる形にはしない。
            nextButtonLabel: offerSummaryQuiz
                ? l10n.learnGoToSummaryQuiz
                : l10n.learnNextSentence,
            onNextSentence:
                offerSummaryQuiz ? _startSummaryQuiz : _proceedToNextSentence,
          ),
        ),
      LearningStage.summaryQuiz => Scaffold(
          appBar: AppBar(
            title: Text(l10n.learnSummaryQuizTitle),
            automaticallyImplyLeading: false,
            actions: const [QuizProgressCounter()],
          ),
          body: QuizScreen(
            showAppBar: false,
            title: l10n.learnSummaryQuizTitle,
            showVocabScoreTransition: true,
            // ここを抜けるとセットを使い切っているので、次は新しい5本を作る。
            // 「次の例文へ」だと1本だけ足すように読めるので名前を分ける。
            nextButtonLabel: l10n.learnNextSet,
            onNextSentence: _proceedToNextSentence,
          ),
        ),
    };
  }
}
