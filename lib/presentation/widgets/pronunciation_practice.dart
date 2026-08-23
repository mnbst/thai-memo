// =============================================================================
// pronunciation_practice.dart
// 例文詳細画面の発音練習セクション。
//
// お手本を聞いたあとに自分で発声し、音節ごとに声調が合っているかを返す。
// 端末TTSからは再生位置が取れないため、お手本と同時に歌うカラオケ型ではなく
// 「聞く → 録音 → 重ねて比較」の逐次型。横軸は時間ではなく音節。
//
// 結果は語ごとに集約して見せる。文が20〜30音節になると音節をそのまま並べても
// 読めないため。語をタップするとその語のカーブを開く。
// =============================================================================

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/pronunciation/pronunciation_analyzer.dart';
import '../../core/pronunciation/pronunciation_coach.dart';
import '../../core/pronunciation/pronunciation_scorer.dart';
import '../../core/pronunciation/segment_coach.dart';
import '../../core/pronunciation/transcript_match.dart';
import '../../core/pronunciation/word_verdict.dart';
import '../../core/thai_tone_analyzer.dart';
import '../../data/models/word_breakdown.dart';
import '../../domain/sentence_tone_spans.dart';
import '../../l10n/app_localizations.dart';
import '../providers/pronunciation_provider.dart';
import '../providers/pronunciation_quota_provider.dart';
import '../providers/remaining_quota_provider.dart';
import '../screens/paywall_screen.dart';

/// 判定の3段階に対応する色。
///
/// 「惜しい」を必ず用意する。合っている／違うの2値だと挫折するため。
Color _verdictColor(ToneVerdict verdict, ColorScheme scheme) {
  switch (verdict) {
    case ToneVerdict.correct:
      return const Color(0xFF2E7D32);
    case ToneVerdict.close:
      return const Color(0xFFEF6C00);
    case ToneVerdict.wrong:
      return scheme.error;
    case ToneVerdict.unscored:
      return scheme.outline;
  }
}

String _verdictLabel(ToneVerdict verdict, L10n l10n) {
  switch (verdict) {
    case ToneVerdict.correct:
      return l10n.pronunciationVerdictCorrect;
    case ToneVerdict.close:
      return l10n.pronunciationVerdictClose;
    case ToneVerdict.wrong:
      return l10n.pronunciationVerdictWrong;
    case ToneVerdict.unscored:
      return l10n.pronunciationVerdictUnscored;
  }
}

/// 語をタップしたときに出す「通じたか」の一行。帯には出さない。
String? _recognitionLabel(WordRecognition recognition, L10n l10n) {
  switch (recognition) {
    case WordRecognition.recognized:
      return l10n.pronunciationSpeechRecognized;
    case WordRecognition.missing:
      return l10n.pronunciationSpeechMissing;
    case WordRecognition.unavailable:
      // 判定していない。判定して駄目だったことと混同させない。
      return null;
  }
}

class PronunciationPractice extends ConsumerWidget {
  const PronunciationPractice({
    super.key,
    required this.sentenceId,
    required this.words,
    required this.scope,
    this.thaiText = '',
    this.showHeader = true,
    this.resultKey,
    this.contourKey,
  });

  /// 保存済み例文のID。未保存（null）の例文では練習させない。
  final String? sentenceId;
  final List<WordBreakdown> words;

  /// 例文のタイ語。空白（節の切れ目）の位置を声調のお手本に反映するために要る。
  final String thaiText;

  /// 「発音してみる」の見出し行を出すか。
  /// マイクボタンから開く場合は入口の直下に出るので見出しは重複する。
  final bool showHeader;

  /// 置き場所の識別子（例: 'home_card' / 'detail'）。
  /// 同じ例文でもここが違えば判定結果は共有されない。
  final String scope;

  /// 初回ガイドで判定結果を指すためのキー。語ごとの帯に付く。
  /// 判定前は対象そのものが無い（案内も出せない）。
  final GlobalKey? resultKey;

  /// 語を選んだときに開くカーブのカード（初回ガイドのスポット対象）。
  final GlobalKey? contourKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = sentenceId;
    if (id == null) return const SizedBox.shrink();

    final spans = buildSentenceToneSpans(words, thaiText: thaiText);
    // 音節データが無い例文では練習できない。導線ごと出さない。
    if (spans.isEmpty) return const SizedBox.shrink();

    final l10n = L10n.of(context);
    // 体験中も課金と同じく無制限。
    final isPremium = ref.watch(effectivePremiumProvider);
    // free でも毎日少しだけ使える。使ったことがない機能には課金できないため。
    final used = ref.watch(pronunciationQuotaProvider);
    final remaining = freeDailyPronunciationChecks - used;
    final locked = !isPremium && remaining <= 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showHeader) ...[
          Row(
            children: [
              Icon(
                Icons.mic_none,
                size: 16,
                color: Theme.of(context).colorScheme.secondary,
              ),
              const SizedBox(width: 6),
              Text(
                l10n.pronunciationTitle,
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        if (locked)
          _PremiumLock(l10n: l10n)
        else ...[
          _PracticeBody(
            sentenceId: id,
            scope: scope,
            spans: spans,
            l10n: l10n,
            countsAgainstQuota: !isPremium,
            resultKey: resultKey,
            contourKey: contourKey,
          ),
          if (!isPremium) ...[
            const SizedBox(height: 6),
            Text(
              l10n.pronunciationFreeRemaining(remaining),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ],
      ],
    );
  }
}

/// 無料枠を使い切った free ユーザー向けの案内。録音ボタンの代わりに置く。
class _PremiumLock extends StatelessWidget {
  const _PremiumLock({required this.l10n});

  final L10n l10n;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => PaywallBottomSheet.show(context, source: 'pronunciation'),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(Icons.lock_outline, size: 18, color: scheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.pronunciationLimitTitle,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    l10n.pronunciationLimitBody,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PracticeBody extends ConsumerWidget {
  const _PracticeBody({
    required this.sentenceId,
    required this.scope,
    required this.spans,
    required this.l10n,
    required this.countsAgainstQuota,
    required this.resultKey,
    required this.contourKey,
  });

  final String sentenceId;
  final String scope;
  final SentenceToneSpans spans;
  final L10n l10n;

  /// free のときだけ true。採点が成立した回だけ枠を消費する。
  final bool countsAgainstQuota;

  /// 初回ガイドが判定結果を指すためのキー。
  final GlobalKey? resultKey;

  /// 初回ガイドがカーブのカードを指すためのキー。
  final GlobalKey? contourKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = pronunciationControllerProvider(
      (sentenceId: sentenceId, scope: scope),
    );
    final state = ref.watch(provider);
    final controller = ref.read(provider.notifier);

    switch (state.phase) {
      case PronunciationPhase.permissionDenied:
        return _PermissionNotice(l10n: l10n);

      case PronunciationPhase.analyzing:
        return _StatusRow(
          icon: Icons.hourglass_empty,
          label: l10n.pronunciationAnalyzing,
        );

      case PronunciationPhase.result:
        final result = state.result;
        if (result == null) return const SizedBox.shrink();
        return _ResultView(
          resultKey: resultKey,
          contourKey: contourKey,
          result: result,
          recognition: state.recognition,
          recognitionStatus: state.recognitionStatus,
          spans: spans,
          selectedWordIndex: state.selectedWordIndex,
          onSelectWord: controller.toggleWord,
          onRetry: () {
            controller.reset();
            // 結果を畳むと画面が縮んで、直前まで見ていた位置が例文から
            // 大きくずれる。言い直すには例文をもう一度見たいので先頭へ戻す。
            Scrollable.maybeOf(context)?.position.animateTo(
                  0,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOut,
                );
          },
          l10n: l10n,
        );

      case PronunciationPhase.idle:
      case PronunciationPhase.recording:
        return _RecordButton(
          recording: state.phase == PronunciationPhase.recording,
          onStart: controller.startRecording,
          onStop: () async {
            await controller.stopAndAnalyze(
              tones: spans.tones,
              shortSyllables: spans.shortSyllables,
              syllablePoints: spans.syllablePoints,
              clauseStarts: spans.clauseStarts,
              syllableLabels: spans.syllableLabels,
              expectedWords: spans.words.map((w) => w.wordText).toList(),
            );
            // 声が小さい・音節が取れない等で採点できなかった回は消費しない。
            final scored = ref.read(provider).result?.isScored ?? false;
            if (countsAgainstQuota && scored) {
              await ref.read(pronunciationQuotaProvider.notifier).consume();
            }
          },
          l10n: l10n,
        );
    }
  }
}

/// 押しっぱなしで録音するボタン。
///
/// 無音での自動停止は入れない。タイ語は語間に無音が入りにくく、
/// 途中で切れて誤判定になる。
/// 押している間だけ録音するボタン。
///
/// 録音中は波形バーと枠の明滅で「今拾っている」ことを見せる。端末からは
/// 入力レベルが取れないので波形は実測ではなく一定周期のアニメーション。
/// 意味は「録音中」であって音量ではない。
class _RecordButton extends StatefulWidget {
  const _RecordButton({
    required this.recording,
    required this.onStart,
    required this.onStop,
    required this.l10n,
  });

  final bool recording;
  final Future<void> Function() onStart;
  final Future<void> Function() onStop;
  final L10n l10n;

  @override
  State<_RecordButton> createState() => _RecordButtonState();
}

class _RecordButtonState extends State<_RecordButton>
    with SingleTickerProviderStateMixin {
  /// 波形と枠の明滅を回す。録音していない間は止めて再描画も起こさない。
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  /// アイコンと波形の置き場。切り替えで文字がずれないよう幅を固定する。
  static const double _indicatorWidth = 26;
  static const double _indicatorHeight = 18;
  static const int _barCount = 5;

  @override
  void initState() {
    super.initState();
    if (widget.recording) _pulse.repeat();
  }

  @override
  void didUpdateWidget(_RecordButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.recording == oldWidget.recording) return;
    if (widget.recording) {
      _pulse.repeat();
    } else {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = widget.recording
        ? widget.l10n.pronunciationRecording
        : widget.l10n.pronunciationHoldToSpeak;

    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTapDown: (_) => widget.onStart(),
        onTapUp: (_) => widget.onStop(),
        onTapCancel: () => widget.onStop(),
        child: AnimatedBuilder(
          animation: _pulse,
          builder: (context, _) {
            // 0→1→0 を1周期でなぞる明滅の位相。
            final wave = 0.5 + 0.5 * math.sin(_pulse.value * 2 * math.pi);
            return Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: widget.recording
                    ? scheme.error.withValues(alpha: 0.10 + 0.08 * wave)
                    : scheme.primaryContainer.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
                // 枠は常に敷く。録音中だけ足すと高さが変わって跳ねる。
                border: Border.all(
                  width: 1.5,
                  color: widget.recording
                      ? scheme.error.withValues(alpha: 0.25 + 0.4 * wave)
                      : Colors.transparent,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: _indicatorWidth,
                    height: _indicatorHeight,
                    child: widget.recording
                        ? _buildBars(scheme)
                        : Center(
                            child: Icon(
                              Icons.mic,
                              size: 18,
                              color: scheme.primary,
                            ),
                          ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  /// 録音中の波形バー。バーごとに位相をずらして左から波が流れて見えるようにする。
  Widget _buildBars(ColorScheme scheme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: List.generate(_barCount, (index) {
        final phase = _pulse.value * 2 * math.pi + index * 0.8;
        final level = 0.5 + 0.5 * math.sin(phase);
        return Container(
          width: 3,
          height: 5 + (_indicatorHeight - 5) * level,
          decoration: BoxDecoration(
            color: scheme.error,
            borderRadius: BorderRadius.circular(2),
          ),
        );
      }),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Theme.of(context).colorScheme.outline),
        const SizedBox(width: 8),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _PermissionNotice extends StatelessWidget {
  const _PermissionNotice({required this.l10n});

  final L10n l10n;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.pronunciationPermissionTitle,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 4),
        Text(
          l10n.pronunciationPermissionBody,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _ResultView extends StatelessWidget {
  const _ResultView({
    required this.resultKey,
    required this.contourKey,
    required this.result,
    required this.recognition,
    required this.recognitionStatus,
    required this.spans,
    required this.selectedWordIndex,
    required this.onSelectWord,
    required this.onRetry,
    required this.l10n,
  });

  /// 初回ガイドのスポット対象（語ごとの帯）に付けるキー。
  final GlobalKey? resultKey;

  /// 初回ガイドのスポット対象（カーブのカード）に付けるキー。
  final GlobalKey? contourKey;
  final PronunciationResult result;
  final List<WordRecognition> recognition;

  /// 発音の判定が使えなかった理由コード。案内の出し分けに使う。
  final String recognitionStatus;
  final SentenceToneSpans spans;
  final int? selectedWordIndex;
  final void Function(int) onSelectWord;
  final VoidCallback onRetry;
  final L10n l10n;

  /// 音声認識まで行えた端末か。1語でも判定できていれば真。
  bool get _hasRecognition =>
      recognition.any((r) => r != WordRecognition.unavailable);

  String? get _failureMessage {
    switch (result.failure) {
      case PronunciationFailure.tooQuiet:
        return l10n.pronunciationTooQuiet;
      case PronunciationFailure.noSpeakerRange:
        return l10n.pronunciationNoSpeakerRange;
      case PronunciationFailure.noSyllables:
        return l10n.pronunciationNoSyllables;
      case PronunciationFailure.captureFailed:
        return l10n.pronunciationCaptureFailed;
      case PronunciationFailure.none:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final failure = _failureMessage;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (failure != null)
          Text(failure, style: theme.textTheme.bodySmall)
        else ...[
          // 抑揚が無いときは点数を出さない。平坦に読むと中平声だけが偶然合って
          // 点数が伸びるため、数字より「何をすべきか」を返す。
          if (result.isMonotone)
            Text(
              l10n.pronunciationMonotone,
              style: theme.textTheme.bodyMedium,
            )
          else
            Text(
              l10n.pronunciationScore(result.overallScore.round()),
              style: theme.textTheme.titleMedium,
            ),
          const SizedBox(height: 8),
          KeyedSubtree(
            key: resultKey,
            child: _WordChips(
              result: result,
              recognition: recognition,
              spans: spans,
              selectedWordIndex: selectedWordIndex,
              onSelectWord: onSelectWord,
            ),
          ),
          const SizedBox(height: 6),
          _BandLegend(
            l10n: l10n,
            hasRecognition: _hasRecognition,
            recognitionStatus: recognitionStatus,
          ),
          if (selectedWordIndex != null)
            // カーブ・直す点・言い直しの3つで1つの流れなので、初回ガイドの
            // 強調も「もう一度」まで含める。直す点だけ見せて終わると、
            // その場で言い直せることに気づかれない。
            KeyedSubtree(
              key: contourKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),
                  _WordContourCard(
                    scores: _scoresOfWord(result, spans, selectedWordIndex!),
                    recognition: selectedWordIndex! < recognition.length
                        ? recognition[selectedWordIndex!]
                        : WordRecognition.unavailable,
                    l10n: l10n,
                  ),
                  // 声調の直し方は初回の結果には出さない。玄人向けの細かさ
                  // なので、語をタップして自分から中を開いた人にだけ、
                  // その語の分を1つ出す。
                  if (!result.isMonotone) ...[
                    const SizedBox(height: 8),
                    _CoachCard(
                      tip: _coachingTipOfWord(
                        result,
                        spans,
                        recognition,
                        selectedWordIndex!,
                      ),
                      l10n: l10n,
                    ),
                  ],
                  const SizedBox(height: 8),
                  _retryButton(l10n),
                ],
              ),
            )
          else ...[
            const SizedBox(height: 6),
            Text(
              l10n.pronunciationTapWordHint,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ],
        // 語を開いている間は強調の中に置いてあるので、ここでは出さない。
        if (failure != null || selectedWordIndex == null) ...[
          const SizedBox(height: 8),
          _retryButton(l10n),
        ],
      ],
    );
  }

  Widget _retryButton(L10n l10n) => Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh, size: 18),
          label: Text(l10n.pronunciationRetry),
        ),
      );
}

List<SyllableScore> _scoresOfWord(
  PronunciationResult result,
  SentenceToneSpans spans,
  int wordIndex,
) {
  if (wordIndex >= spans.words.length) return const [];
  final span = spans.words[wordIndex];
  return result.syllables
      .where((s) => span.contains(s.syllableIndex))
      .toList();
}

/// 選んだ語だけの助言を1つ選ぶ。
///
/// 文全体で最多の外しではなく、**開いた語の中の**外しを見る。カーブと助言が
/// 別の語を指していると、どこを直せばいいのか分からなくなる。
CoachingTip? _coachingTipOfWord(
  PronunciationResult result,
  SentenceToneSpans spans,
  List<WordRecognition> recognition,
  int wordIndex,
) {
  if (wordIndex >= spans.words.length) return null;
  final word = spans.words[wordIndex];
  return coachingTipOf(
    _scoresOfWord(result, spans, wordIndex),
    // 語1つ分に切り出して渡す。助言側は語順の列として扱うので、
    // 添字0がこの語になる。
    recognition: wordIndex < recognition.length
        ? [recognition[wordIndex]]
        : const [],
    wordTexts: [word.wordText],
    // 音節の表記は文全体の音節順で引く（SyllableScore.syllableIndex が全体の順）。
    toneMarks: spans.toneMarks,
    romans: spans.syllableRomans,
    // 声調が合っているのに通じなかった語では、子音・母音のうち
    // 日本語話者が最も外しやすい点を1つ出す。
    segmentPointOfWord: (_) => spans.segmentPointOfWord(wordIndex),
  );
}

/// 次の1回で直す点を1つだけ出す。直すところが無ければ何も描かない。
class _CoachCard extends StatelessWidget {
  const _CoachCard({required this.tip, required this.l10n});

  final CoachingTip? tip;
  final L10n l10n;

  String _text(CoachingTip tip) {
    switch (tip.issue) {
      case CoachIssue.notRecognized:
        final segment = tip.segment;
        // どの音を外したかは分からない。優先順位で選んだ1点が取れたときだけ、
        // その音の直し方を出す。取れなければ語を名指しするだけに留める。
        if (segment != null) {
          return _segmentText(segment, tip.wordText ?? '', l10n);
        }
        return l10n.pronunciationCoachNotRecognized(tip.wordText ?? '');
      case CoachIssue.shape:
        switch (tip.tone) {
          case ThaiTone.mid:
            return l10n.pronunciationCoachShapeMid;
          case ThaiTone.low:
            return l10n.pronunciationCoachShapeLow;
          case ThaiTone.falling:
            return l10n.pronunciationCoachShapeFalling;
          case ThaiTone.high:
            return l10n.pronunciationCoachShapeHigh;
          case ThaiTone.rising:
            return l10n.pronunciationCoachShapeRising;
          case ThaiTone.unknown:
          case null:
            // coachingTipOf が除外しているので到達しない。
            return '';
        }
      case CoachIssue.step:
        final tone = tip.tone!.displayName(l10n);
        return tip.stepUp
            ? l10n.pronunciationCoachStepUp(tone)
            : l10n.pronunciationCoachStepDown(tone);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tip = this.tip;
    if (tip == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lightbulb_outline, size: 18, color: cs.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      l10n.pronunciationCoachLead,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    // ローマ字を優先する。声調記号（◌้）は表記の知識が要るが、
                    // ローマ字は声調が母音の上に直接乗るので、どの音をどう
                    // 動かすのかがそのまま読める。取れない語では記号に落ちる。
                    if (_syllableLabel(tip).isNotEmpty) ...[
                      const SizedBox(width: 6),
                      _ToneMarkChip(label: _syllableLabel(tip)),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  _text(tip),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 子音・母音の直し方を1行にする。
String _segmentText(SegmentPoint point, String word, L10n l10n) {
  switch (point.issue) {
    case SegmentIssue.unaspirated:
      return l10n.pronunciationSegmentUnaspirated(
        word,
        point.label,
        point.aspirated,
      );
    case SegmentIssue.finalStop:
      switch (point.sound) {
        case 'p':
          return l10n.pronunciationSegmentFinalP(word);
        case 'k':
          return l10n.pronunciationSegmentFinalK(word);
        default:
          return l10n.pronunciationSegmentFinalT(word);
      }
    case SegmentIssue.ngInitial:
      return l10n.pronunciationSegmentNgInitial(word);
    case SegmentIssue.finalNasal:
      switch (point.sound) {
        case 'ng':
          return l10n.pronunciationSegmentFinalNg(word);
        case 'm':
          return l10n.pronunciationSegmentFinalM(word);
        default:
          return l10n.pronunciationSegmentFinalN(word);
      }
    case SegmentIssue.shortVowel:
      return l10n.pronunciationSegmentShortVowel(word, point.label);
    case SegmentIssue.thaiVowel:
      switch (point.vowel) {
        case ThaiVowelSound.ae:
          return l10n.pronunciationSegmentVowelAe(word);
        case ThaiVowelSound.oe:
          return l10n.pronunciationSegmentVowelOe(word);
        case ThaiVowelSound.aw:
          return l10n.pronunciationSegmentVowelAw(word);
        case ThaiVowelSound.ue:
        case null:
          return l10n.pronunciationSegmentVowelUe(word);
      }
  }
}

/// コーチングが指した音節をどう見せるか。
///
/// ローマ字が取れていればそれ。無ければタイ文字の声調記号を点線円（U+25CC）に
/// 載せる（結合文字なので、単独で置くと土台を失って崩れる）。
String _syllableLabel(CoachingTip tip) {
  if (tip.roman.isNotEmpty) return tip.roman;
  if (tip.toneMark.isNotEmpty) return '◌${tip.toneMark}';
  return '';
}

/// コーチングが指した音節を1つ表示する。
class _ToneMarkChip extends StatelessWidget {
  const _ToneMarkChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelMedium?.copyWith(color: cs.primary),
      ),
    );
  }
}

/// 語ごとの判定を色帯で並べる。
class _WordChips extends StatelessWidget {
  const _WordChips({
    required this.result,
    required this.recognition,
    required this.spans,
    required this.selectedWordIndex,
    required this.onSelectWord,
  });

  final PronunciationResult result;
  final List<WordRecognition> recognition;
  final SentenceToneSpans spans;
  final int? selectedWordIndex;
  final void Function(int) onSelectWord;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: List.generate(spans.words.length, (index) {
        final span = spans.words[index];
        final verdict = combinedWordVerdict(
          toneVerdictOfWord(_scoresOfWord(result, spans, index)),
          index < recognition.length
              ? recognition[index]
              : WordRecognition.unavailable,
        );
        final color = _verdictColor(verdict, scheme);
        final selected = selectedWordIndex == index;

        return InkWell(
          onTap: () => onSelectWord(index),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: selected ? color.withValues(alpha: 0.12) : null,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text.rich(
                  TextSpan(
                    text: span.wordText,
                    children: [
                      // 発音表記。色帯で「直せ」と言われても、読み方が出て
                      // いなければ何を直すのか分からない。
                      if (span.pronunciation.isNotEmpty)
                        TextSpan(
                          text: ' (${span.pronunciation})',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: scheme.outline,
                                  ),
                        ),
                    ],
                  ),
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 3),
                // 帯は1本。声調と発音を合わせた「言い直す必要があるか」だけを
                // 伝え、どちらを外したかは語をタップして見せる。
                _Band(color: color),
              ],
            ),
          ),
        );
      }),
    );
  }
}

class _Band extends StatelessWidget {
  const _Band({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        height: 3,
        width: double.infinity,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(2),
        ),
      );
}

/// 帯が何を表すかの凡例。発音が判定できなかった端末では、その理由を出す。
class _BandLegend extends StatelessWidget {
  const _BandLegend({
    required this.l10n,
    required this.hasRecognition,
    required this.recognitionStatus,
  });

  final L10n l10n;
  final bool hasRecognition;
  final String recognitionStatus;

  /// 理由コードごとの案内。**直せるものは直し方まで出す。**
  ///
  /// タイ語の音声入力が入っていない端末が大半で、これは端末の設定で直る。
  /// 「非対応です」で終わらせると、直せる人まで諦める。
  (String, String?) get _notice {
    switch (recognitionStatus) {
      case 'no_on_device_asset':
        return (
          l10n.pronunciationSpeechNoAsset,
          l10n.pronunciationSpeechNoAssetHow,
        );
      case 'auth_denied':
        return (l10n.pronunciationSpeechAuthDenied, null);
      case 'android_unsupported':
        return (l10n.pronunciationSpeechAndroid, null);
      default:
        return (l10n.pronunciationSpeechUnavailable, null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;

    // 判定できないことと、判定して駄目だったことを混同させない。
    if (hasRecognition) {
      return Text(l10n.pronunciationBandCombined, style: style);
    }

    final (message, how) = _notice;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(message, style: style),
        if (how != null) ...[
          const SizedBox(height: 2),
          Text(
            how,
            style: style?.copyWith(
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
        ],
      ],
    );
  }
}

/// 選択した語のお手本カーブと自分のカーブを重ねて出す。
class _WordContourCard extends StatelessWidget {
  const _WordContourCard({
    required this.scores,
    required this.recognition,
    required this.l10n,
  });

  final List<SyllableScore> scores;
  final WordRecognition recognition;
  final L10n l10n;

  @override
  Widget build(BuildContext context) {
    if (scores.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final recognitionLabel = _recognitionLabel(recognition, l10n);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _LegendDot(color: scheme.outline, label: l10n.pronunciationReference),
              const SizedBox(width: 12),
              _LegendDot(color: scheme.primary, label: l10n.pronunciationYours),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 72,
            width: double.infinity,
            child: CustomPaint(
              painter: _ContourPainter(
                scores: scores,
                referenceColor: scheme.outline,
                userColor: scheme.primary,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 4,
            children: scores
                .map((s) => Text(
                      '${s.tone.name} · ${_verdictLabel(s.verdict, l10n)}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: _verdictColor(s.verdict, scheme),
                          ),
                    ))
                .toList(),
          ),
          // 帯を1本にしたぶん、どちらの軸を外したかはここで分ける。
          if (recognitionLabel != null) ...[
            const SizedBox(height: 4),
            Text(
              recognitionLabel,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: recognition == WordRecognition.missing
                        ? scheme.error
                        : null,
                  ),
            ),
          ],
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 10, height: 3, color: color),
        const SizedBox(width: 4),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

/// 音節を横に並べ、お手本と録音のピッチを重ねて描く。
///
/// 横軸は時間ではなく音節。TTSから再生位置が取れないため、時間軸で並べても
/// お手本と揃わない。
class _ContourPainter extends CustomPainter {
  _ContourPainter({
    required this.scores,
    required this.referenceColor,
    required this.userColor,
  });

  final List<SyllableScore> scores;
  final Color referenceColor;
  final Color userColor;

  /// 縦軸に取るピッチの範囲（正規化済みの単位）。
  static const double _yRange = 1.5;

  @override
  void paint(Canvas canvas, Size size) {
    if (scores.isEmpty) return;

    final syllableWidth = size.width / scores.length;

    double yOf(double value) {
      final clamped = value.clamp(-_yRange, _yRange);
      return size.height * (0.5 - clamped / (_yRange * 2));
    }

    // 中心線。
    final centerPaint = Paint()
      ..color = referenceColor.withValues(alpha: 0.25)
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(0, yOf(0)),
      Offset(size.width, yOf(0)),
      centerPaint,
    );

    for (var i = 0; i < scores.length; i++) {
      final left = syllableWidth * i;

      // 音節の区切り線。
      if (i > 0) {
        canvas.drawLine(
          Offset(left, 0),
          Offset(left, size.height),
          Paint()
            ..color = referenceColor.withValues(alpha: 0.2)
            ..strokeWidth = 1,
        );
      }

      _drawSeries(
        canvas,
        scores[i].referenceValues,
        left,
        syllableWidth,
        yOf,
        Paint()
          ..color = referenceColor
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round,
      );
      _drawSeries(
        canvas,
        scores[i].queryValues,
        left,
        syllableWidth,
        yOf,
        Paint()
          ..color = userColor
          ..strokeWidth = 2.5
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  void _drawSeries(
    Canvas canvas,
    List<double> values,
    double left,
    double width,
    double Function(double) yOf,
    Paint paint,
  ) {
    if (values.length < 2) return;

    // 音節1つぶんの幅に、点数によらず均等に割り付ける。録音側は
    // 対応づいたフレーム数が音節ごとに違うため、正規化した位置で描く。
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = left + width * (i / (values.length - 1));
      // 端が枠線と重ならないように少しだけ内側に寄せる。
      final inset = math.min(2.0, width / 4);
      final adjusted = left + inset + (x - left) * (width - inset * 2) / width;
      final y = yOf(values[i]);
      if (i == 0) {
        path.moveTo(adjusted, y);
      } else {
        path.lineTo(adjusted, y);
      }
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_ContourPainter oldDelegate) =>
      oldDelegate.scores != scores ||
      oldDelegate.referenceColor != referenceColor ||
      oldDelegate.userColor != userColor;
}
