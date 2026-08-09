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
import '../../core/pronunciation/pronunciation_scorer.dart';
import '../../core/pronunciation/transcript_match.dart';
import '../../core/pronunciation/word_verdict.dart';
import '../../data/models/word_breakdown.dart';
import '../../domain/sentence_tone_spans.dart';
import '../../l10n/app_localizations.dart';
import '../providers/pronunciation_provider.dart';
import '../providers/subscription_provider.dart';
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
  });

  /// 保存済み例文のID。未保存（null）の例文では練習させない。
  final String? sentenceId;
  final List<WordBreakdown> words;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = sentenceId;
    if (id == null) return const SizedBox.shrink();

    final spans = buildSentenceToneSpans(words);
    // 音節データが無い例文では練習できない。導線ごと出さない。
    if (spans.isEmpty) return const SizedBox.shrink();

    final l10n = L10n.of(context);
    final isPremium = ref.watch(subscriptionControllerProvider).isPremium;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
        if (!isPremium)
          _PremiumLock(l10n: l10n)
        else
          _PracticeBody(sentenceId: id, spans: spans, l10n: l10n),
      ],
    );
  }
}

/// free ユーザー向けの案内。録音ボタンの代わりに置く。
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
                    l10n.pronunciationPremiumTitle,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    l10n.pronunciationPremiumBody,
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
    required this.spans,
    required this.l10n,
  });

  final String sentenceId;
  final SentenceToneSpans spans;
  final L10n l10n;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = pronunciationControllerProvider(sentenceId);
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
          onStop: () => controller.stopAndAnalyze(
            tones: spans.tones,
            shortSyllables: spans.shortSyllables,
            syllablePoints: spans.syllablePoints,
            syllableLabels: spans.syllableLabels,
            expectedWords: spans.words.map((w) => w.wordText).toList(),
          ),
          l10n: l10n,
        );
    }
  }
}

/// 押しっぱなしで録音するボタン。
///
/// 無音での自動停止は入れない。タイ語は語間に無音が入りにくく、
/// 途中で切れて誤判定になる。
class _RecordButton extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: recording
          ? l10n.pronunciationRecording
          : l10n.pronunciationHoldToSpeak,
      child: GestureDetector(
        onTapDown: (_) => onStart(),
        onTapUp: (_) => onStop(),
        onTapCancel: () => onStop(),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: recording
                ? scheme.error.withValues(alpha: 0.12)
                : scheme.primaryContainer.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                recording ? Icons.fiber_manual_record : Icons.mic,
                size: 18,
                color: recording ? scheme.error : scheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                recording
                    ? l10n.pronunciationRecording
                    : l10n.pronunciationHoldToSpeak,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
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
    required this.result,
    required this.recognition,
    required this.recognitionStatus,
    required this.spans,
    required this.selectedWordIndex,
    required this.onSelectWord,
    required this.onRetry,
    required this.l10n,
  });

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
          _WordChips(
            result: result,
            recognition: recognition,
            spans: spans,
            selectedWordIndex: selectedWordIndex,
            onSelectWord: onSelectWord,
          ),
          const SizedBox(height: 6),
          _BandLegend(
            l10n: l10n,
            hasRecognition: _hasRecognition,
            recognitionStatus: recognitionStatus,
          ),
          if (selectedWordIndex != null) ...[
            const SizedBox(height: 8),
            _WordContourCard(
              scores: _scoresOfWord(result, spans, selectedWordIndex!),
              recognition: selectedWordIndex! < recognition.length
                  ? recognition[selectedWordIndex!]
                  : WordRecognition.unavailable,
              l10n: l10n,
            ),
          ] else ...[
            const SizedBox(height: 6),
            Text(
              l10n.pronunciationTapWordHint,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ],
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh, size: 18),
          label: Text(l10n.pronunciationRetry),
        ),
      ],
    );
  }
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
                Text(
                  span.wordText,
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
