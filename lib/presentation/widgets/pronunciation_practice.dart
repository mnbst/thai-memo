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

import 'dart:async';
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
import '../providers/tts_provider.dart';

/// 判定の3段階に対応する色。
///
/// 「惜しい」を必ず用意する。合っている／違うの2値だと挫折するため。
Color verdictColor(ToneVerdict verdict, ColorScheme scheme) {
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = sentenceId;
    if (id == null) return const SizedBox.shrink();

    final spans = buildSentenceToneSpans(words, thaiText: thaiText);
    // 音節データが無い例文では練習できない。導線ごと出さない。
    if (spans.isEmpty) return const SizedBox.shrink();

    final l10n = L10n.of(context);

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
        _PracticeBody(
          sentenceId: id,
          scope: scope,
          spans: spans,
          l10n: l10n,
        ),
      ],
    );
  }
}

class _PracticeBody extends ConsumerWidget {
  const _PracticeBody({
    required this.sentenceId,
    required this.scope,
    required this.spans,
    required this.l10n,
  });

  final String sentenceId;
  final String scope;
  final SentenceToneSpans spans;
  final L10n l10n;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = pronunciationControllerProvider(
      (sentenceId: sentenceId, scope: scope),
    );
    final state = ref.watch(provider);
    final controller = ref.read(provider.notifier);

    if (state.phase == PronunciationPhase.permissionDenied) {
      return _PermissionNotice(l10n: l10n);
    }

    final result =
        state.phase == PronunciationPhase.result ? state.result : null;

    // 結果を畳むのは「もう一度」を押したときだけにする。押しっぱなしの録音と
    // 同じボタンに載せると、押した瞬間に結果が畳まれてボタンごと動き、
    // 指を離していないのに離した扱いになる。畳む操作と話す操作は分ける。
    void collapseResult() {
      controller.reset();
      // 結果を畳むと画面が縮んで、直前まで見ていた位置が例文から大きくずれる。
      // 言い直すには例文をもう一度見たいので先頭へ戻す。
      Scrollable.maybeOf(context)?.position.animateTo(
            0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
    }

    Widget speakButton() {
      return _RecordButton(
        recording: state.phase == PronunciationPhase.recording,
        label: l10n.pronunciationHoldToSpeak,
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
        },
        l10n: l10n,
      );
    }

    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      alignment: Alignment.topCenter,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (result != null) ...[
            _ResultView(
              result: result,
              recognition: state.recognition,
              recognitionStatus: state.recognitionStatus,
              spans: spans,
              selectedWordIndex: state.selectedWordIndex,
              onSelectWord: controller.toggleWord,
              l10n: l10n,
            ),
            const SizedBox(height: 12),
          ],
          // 判定中はボタンの位置のまま回す。灰色の一行に差し替えると、
          // 押しても何も起きなかったように見える。
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: switch (state.phase) {
              PronunciationPhase.analyzing => _AnalyzingBar(l10n: l10n),
              // 結果を見ている間は、まず畳ませる。畳んでから押しっぱなしで話す。
              PronunciationPhase.result => _CollapseResultButton(
                  label: l10n.pronunciationRetry,
                  onTap: collapseResult,
                ),
              _ => speakButton(),
            },
          ),
        ],
      ),
    );
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
    required this.label,
    required this.onStart,
    required this.onStop,
    required this.l10n,
  });

  final bool recording;

  /// 押していないときの文言。判定のあとは「もう一度」に変わる。
  final String label;
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
    final label =
        widget.recording ? widget.l10n.pronunciationRecording : widget.label;

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
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: widget.recording
                    ? scheme.error.withValues(alpha: 0.10 + 0.08 * wave)
                    : scheme.primary,
                borderRadius: BorderRadius.circular(14),
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
                              color: scheme.onPrimary,
                            ),
                          ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: widget.recording
                              ? scheme.error
                              : scheme.onPrimary,
                          fontWeight: FontWeight.w700,
                        ),
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

/// 結果を畳んで、話せる状態へ戻すボタン。
///
/// 録音ボタンと同じ形・同じ位置に置く。ここを押すと結果が閉じ、押しっぱなしで
/// 話せる状態に戻る。
class _CollapseResultButton extends StatelessWidget {
  const _CollapseResultButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: scheme.primary,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(width: 1.5, color: Colors.transparent),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.refresh, size: 18, color: scheme.onPrimary),
              const SizedBox(width: 8),
              Text(
                label,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onPrimary,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 判定中の表示。録音ボタンと同じ形・同じ位置に置き換わる。
class _AnalyzingBar extends StatelessWidget {
  const _AnalyzingBar({required this.l10n});

  final L10n l10n;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(width: 1.5, color: Colors.transparent),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: scheme.primary,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            l10n.pronunciationAnalyzing,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
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
    required this.l10n,
  });

  final PronunciationResult result;
  final List<WordRecognition> recognition;

  /// 発音の判定が使えなかった理由コード。案内の出し分けに使う。
  final String recognitionStatus;
  final SentenceToneSpans spans;
  final int? selectedWordIndex;
  final void Function(int) onSelectWord;
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
    if (failure != null) {
      return Text(failure, style: theme.textTheme.bodySmall);
    }

    final selected = selectedWordIndex;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 抑揚が無いときは点数を出さない。平坦に読むと中平声だけが偶然合って
        // 点数が伸びるため、数字より「何をすべきか」を返す。
        if (result.isMonotone)
          Text(
            l10n.pronunciationMonotone,
            style: theme.textTheme.bodyMedium,
          )
        else
          _ScoreHeader(
            result: result,
            recognition: recognition,
            spans: spans,
            l10n: l10n,
          ),
        const SizedBox(height: 12),
        _WordChips(
          result: result,
          recognition: recognition,
          spans: spans,
          selectedWordIndex: selectedWordIndex,
          onSelectWord: onSelectWord,
        ),
        // 判定できる端末では、色の意味は結果ヘッダの内訳が兼ねる。
        // ここに文章を足すと同じことを二度言うだけになる。
        if (!_hasRecognition) ...[
          const SizedBox(height: 8),
          _RecognitionNotice(l10n: l10n, recognitionStatus: recognitionStatus),
        ],
        if (selected != null)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 10),
              _WordContourCard(
                word: selected < spans.words.length
                    ? spans.words[selected]
                    : null,
                scores: _scoresOfWord(result, spans, selected),
                romans: spans.syllableRomans,
                recognition: selected < recognition.length
                    ? recognition[selected]
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
                    selected,
                  ),
                  l10n: l10n,
                ),
              ],
            ],
          )
        else ...[
          const SizedBox(height: 8),
          Text(
            l10n.pronunciationTapWordHintDetail,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

/// 語ごとの最終判定（声調と発音を合わせたもの）を語順で返す。
List<ToneVerdict> _wordVerdicts(
  PronunciationResult result,
  SentenceToneSpans spans,
  List<WordRecognition> recognition,
) =>
    List.generate(
      spans.words.length,
      (index) => combinedWordVerdict(
        toneVerdictOfWord(_scoresOfWord(result, spans, index)),
        index < recognition.length
            ? recognition[index]
            : WordRecognition.unavailable,
      ),
    );

/// 点数のリングと、語ごとの内訳を1行にまとめた結果の見出し。
///
/// 数字だけでは「何語通じたのか」「次にどこを直すのか」が分からない。
/// 点数・通じた語数・次の1語を、この1ブロックで返す。
class _ScoreHeader extends StatelessWidget {
  const _ScoreHeader({
    required this.result,
    required this.recognition,
    required this.spans,
    required this.l10n,
  });

  final PronunciationResult result;
  final List<WordRecognition> recognition;
  final SentenceToneSpans spans;
  final L10n l10n;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final verdicts = _wordVerdicts(result, spans, recognition);

    int countOf(ToneVerdict verdict) =>
        verdicts.where((v) => v == verdict).length;
    final correct = countOf(ToneVerdict.correct);
    final close = countOf(ToneVerdict.close);
    final wrong = countOf(ToneVerdict.wrong);

    // 次に直す語は「ずれている」を優先し、無ければ「惜しい」を拾う。
    final focusIndex = verdicts.contains(ToneVerdict.wrong)
        ? verdicts.indexOf(ToneVerdict.wrong)
        : verdicts.indexOf(ToneVerdict.close);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _ScoreRing(score: result.overallScore, l10n: l10n),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.pronunciationSummaryRecognized(
                  correct,
                  verdicts.length,
                ),
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              if (focusIndex >= 0) ...[
                const SizedBox(height: 2),
                Text(
                  l10n.pronunciationNextFocus(spans.words[focusIndex].wordText),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 6),
              Wrap(
                spacing: 10,
                runSpacing: 2,
                children: [
                  if (correct > 0)
                    _CountChip(
                      color: verdictColor(ToneVerdict.correct, scheme),
                      label: l10n.pronunciationCountCorrect,
                      count: correct,
                    ),
                  if (close > 0)
                    _CountChip(
                      color: verdictColor(ToneVerdict.close, scheme),
                      label: l10n.pronunciationCountClose,
                      count: close,
                    ),
                  if (wrong > 0)
                    _CountChip(
                      color: verdictColor(ToneVerdict.wrong, scheme),
                      label: l10n.pronunciationCountWrong,
                      count: wrong,
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CountChip extends StatelessWidget {
  const _CountChip({
    required this.color,
    required this.label,
    required this.count,
  });

  final Color color;
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          '$label $count',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }
}

/// 点数をリングで見せる。数字だけの1行より、良し悪しが一目で分かる。
class _ScoreRing extends StatelessWidget {
  const _ScoreRing({required this.score, required this.l10n});

  final double score;
  final L10n l10n;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final rounded = score.round();

    return Semantics(
      label: l10n.pronunciationScore(rounded),
      child: SizedBox(
        width: 62,
        height: 62,
        child: CustomPaint(
          painter: _ScoreRingPainter(
            progress: (score / 100).clamp(0.0, 1.0),
            trackColor: scheme.outlineVariant,
            color: scheme.tertiary,
          ),
          child: Center(
            child: Text(
              '$rounded',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ScoreRingPainter extends CustomPainter {
  _ScoreRingPainter({
    required this.progress,
    required this.trackColor,
    required this.color,
  });

  final double progress;
  final Color trackColor;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 5.0;
    final rect = Offset(stroke / 2, stroke / 2) &
        Size(size.width - stroke, size.height - stroke);

    canvas.drawArc(
      rect,
      0,
      math.pi * 2,
      false,
      Paint()
        ..color = trackColor
        ..strokeWidth = stroke
        ..style = PaintingStyle.stroke,
    );
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2 * progress,
      false,
      Paint()
        ..color = color
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(_ScoreRingPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.color != color ||
      oldDelegate.trackColor != trackColor;
}

List<SyllableScore> _scoresOfWord(
  PronunciationResult result,
  SentenceToneSpans spans,
  int wordIndex,
) {
  if (wordIndex >= spans.words.length) return const [];
  final span = spans.words[wordIndex];
  return result.syllables.where((s) => span.contains(s.syllableIndex)).toList();
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
    recognition:
        wordIndex < recognition.length ? [recognition[wordIndex]] : const [],
    wordTexts: [word.wordText],
    // 音節の表記は文全体の音節順で引く（SyllableScore.syllableIndex が全体の順）。
    toneMarks: spans.toneMarks,
    romans: spans.syllableRomans,
    // 声調が合っているのに通じなかった語では、子音・母音のうち
    // 日本語話者が外しやすい点を、観点のグループごとに1つずつ出す。
    segmentPointsOfWord: (_) => spans.segmentPointsOfWord(wordIndex),
  );
}

/// 次の1回で直す点を出す。直すところが無ければ何も描かない。
///
/// 声調は1つだけ。子音・母音は観点のグループごとに1行ずつ並べる
/// （[SegmentGroup]）。同じ観点を並べても直せないが、観点が違えば直す場所も
/// 違うので、末子音だけで埋まらないようにする。
class _CoachCard extends StatelessWidget {
  const _CoachCard({required this.tip, required this.l10n});

  final CoachingTip? tip;
  final L10n l10n;

  /// 助言の本文。子音・母音は観点ごとに1行ずつ並べる。
  List<String> _lines(CoachingTip tip) {
    switch (tip.issue) {
      case CoachIssue.notRecognized:
        // どの音を外したかは分からない。グループごとに選んだ点が取れたときだけ、
        // その音の直し方を出す。取れなければ語を名指しするだけに留める。
        if (tip.segments.isNotEmpty) {
          return [
            for (final segment in tip.segments)
              _segmentText(segment, tip.wordText ?? '', l10n),
          ];
        }
        return [l10n.pronunciationCoachNotRecognized(tip.wordText ?? '')];
      case CoachIssue.shape:
        switch (tip.tone) {
          case ThaiTone.mid:
            return [l10n.pronunciationCoachShapeMid];
          case ThaiTone.low:
            return [l10n.pronunciationCoachShapeLow];
          case ThaiTone.falling:
            return [l10n.pronunciationCoachShapeFalling];
          case ThaiTone.high:
            return [l10n.pronunciationCoachShapeHigh];
          case ThaiTone.rising:
            return [l10n.pronunciationCoachShapeRising];
          case ThaiTone.unknown:
          case null:
            // coachingTipOf が除外しているので到達しない。
            return const [''];
        }
      case CoachIssue.step:
        final tone = tip.tone!.displayName(l10n);
        return [
          tip.stepUp
              ? l10n.pronunciationCoachStepUp(tone)
              : l10n.pronunciationCoachStepDown(tone),
        ];
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
                for (final line in _lines(tip))
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      line,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: cs.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
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
///
/// 2音節以上の語では**音節を名指しする**（[SegmentPoint.syllableText]）。
/// 語だけを指すと、どの音節のことか分からない。
String _segmentText(SegmentPoint point, String wordText, L10n l10n) {
  final word = point.syllableText.isEmpty ? wordText : point.syllableText;
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

/// 語ごとの判定をチップで並べる。
///
/// 判定色は面と枠に出す。3pxの帯だけでは「押せる」ことも「どの語のことか」も
/// 伝わらない。
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final verdicts = _wordVerdicts(result, spans, recognition);

    return Wrap(
      spacing: 7,
      runSpacing: 7,
      children: List.generate(spans.words.length, (index) {
        final span = spans.words[index];
        final color = verdictColor(verdicts[index], scheme);
        final selected = selectedWordIndex == index;

        return InkWell(
          onTap: () => onSelectWord(index),
          borderRadius: BorderRadius.circular(11),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 7),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(11),
              color: color.withValues(alpha: selected ? 0.18 : 0.08),
              border: Border.all(
                color: color.withValues(alpha: selected ? 1 : 0.4),
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(span.wordText, style: theme.textTheme.bodyLarge),
                // 発音表記。色で「直せ」と言われても、読み方が出ていなければ
                // 何を直すのか分からない。
                if (span.pronunciation.isNotEmpty)
                  Text(
                    span.pronunciation,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        );
      }),
    );
  }
}

/// 発音（子音・母音）を判定できなかった端末への案内。
///
/// **直せるものは直し方まで出す。** タイ語の音声入力が入っていない端末が
/// 大半で、これは端末の設定で直る。「非対応です」で終わらせると、直せる人まで
/// 諦める。
class _RecognitionNotice extends StatelessWidget {
  const _RecognitionNotice({
    required this.l10n,
    required this.recognitionStatus,
  });

  final L10n l10n;
  final String recognitionStatus;

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
    final theme = Theme.of(context);
    final style = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final (message, how) = _notice;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(message, style: style),
        if (how != null) ...[
          const SizedBox(height: 2),
          Text(
            how,
            style: style?.copyWith(color: theme.colorScheme.outline),
          ),
        ],
      ],
    );
  }
}

/// 声調の形を1文字で示す。カーブだけでは「下降声」と読めないため、
/// 音節ごとの見出しに声調名と並べて出す。
String _toneArrow(ThaiTone tone) {
  switch (tone) {
    case ThaiTone.mid:
      return '→';
    case ThaiTone.low:
      return '↘';
    case ThaiTone.falling:
      return '⤵';
    case ThaiTone.high:
      return '↗';
    case ThaiTone.rising:
      return '⤴';
    case ThaiTone.unknown:
      return '';
  }
}

/// 選択した語のお手本カーブと自分のカーブを重ねて出す。
///
/// 図だけでは「どこがどう違うのか」までしか分からないので、同じカードから
/// お手本を聞けるようにする。耳で確かめられると判定に納得できる。
class _WordContourCard extends ConsumerWidget {
  const _WordContourCard({
    required this.word,
    required this.scores,
    required this.romans,
    required this.recognition,
    required this.l10n,
  });

  /// 開いている語。読み上げと見出しに使う。
  final WordToneSpan? word;
  final List<SyllableScore> scores;

  /// 文全体の音節ローマ字（[SyllableScore.syllableIndex] で引く）。
  final List<String> romans;
  final WordRecognition recognition;
  final L10n l10n;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (scores.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final recognitionLabel = _recognitionLabel(recognition, l10n);
    final text = word?.wordText ?? '';

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
              Expanded(
                child: Text.rich(
                  TextSpan(
                    text: text,
                    children: [
                      if ((word?.pronunciation ?? '').isNotEmpty)
                        TextSpan(
                          text: '  ${word!.pronunciation}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                  style: theme.textTheme.titleSmall,
                ),
              ),
              if (text.isNotEmpty)
                TextButton.icon(
                  onPressed: () => unawaited(
                    ref.read(ttsServiceProvider).speak(text),
                  ),
                  icon: const Icon(Icons.volume_up, size: 18),
                  label: Text(l10n.pronunciationListenModelWord),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              _LegendDot(
                  color: scheme.outline, label: l10n.pronunciationReference),
              const SizedBox(width: 12),
              _LegendDot(color: scheme.primary, label: l10n.pronunciationYours),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 80,
            width: double.infinity,
            child: CustomPaint(
              painter: _ContourPainter(
                scores: scores,
                referenceColor: scheme.outline,
                userColor: scheme.primary,
              ),
            ),
          ),
          const SizedBox(height: 6),
          // 音節ごとの見出し。カーブの列と横位置を合わせる。
          Row(
            children: scores.map((score) {
              final roman = score.syllableIndex < romans.length
                  ? romans[score.syllableIndex]
                  : '';
              final arrow = _toneArrow(score.tone);
              return Expanded(
                child: Column(
                  children: [
                    if (roman.isNotEmpty)
                      Text(
                        roman,
                        style: theme.textTheme.labelSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    Text(
                      '${score.tone.displayName(l10n)}'
                      '${arrow.isEmpty ? '' : ' $arrow'}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      _verdictLabel(score.verdict, l10n),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: verdictColor(score.verdict, scheme),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
          // 判定は1つにまとめてあるので、どちらの軸を外したかはここで分ける。
          if (recognitionLabel != null) ...[
            const SizedBox(height: 6),
            Text(
              recognitionLabel,
              style: theme.textTheme.bodySmall?.copyWith(
                color: recognition == WordRecognition.missing
                    ? scheme.error
                    : scheme.onSurfaceVariant,
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

  /// 上下に空ける余白。範囲の端まで出た線は枠の外へ半分はみ出して切れて見える。
  /// 線の太さ分だけ内側に寄せる。
  static const double _yInset = 4;

  @override
  void paint(Canvas canvas, Size size) {
    if (scores.isEmpty) return;

    final syllableWidth = size.width / scores.length;
    final usableHeight = math.max(0.0, size.height - _yInset * 2);

    double yOf(double value) {
      final clamped = value.clamp(-_yRange, _yRange);
      return _yInset + usableHeight * (0.5 - clamped / (_yRange * 2));
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
