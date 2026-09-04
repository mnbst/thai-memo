// =============================================================================
// guide_figures.dart
// 使い方ガイド（説明書）に載せる図。
//
// 画面写真は使わない。UIを変えるたび撮り直しになるうえ、言語ごとに要る。
// ここではウィジェットで模式図を描く。文言は l10n から引くので ja/en 両方で
// 成り立ち、配色もテーマに追従する。
// =============================================================================

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/pronunciation/pronunciation_scorer.dart';
import '../../l10n/app_localizations.dart';
import '../screens/paywall_screen.dart';
import 'pronunciation_practice.dart';
import 'vocab_level.dart';

/// 学習のくり返しを1本の流れで示す図。
/// 例文 → クイズのくり返しと、例文5つごとのまとめクイズ。
class GuideLoopFigure extends StatelessWidget {
  const GuideLoopFigure({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    Widget node(String label) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(label, style: theme.textTheme.labelMedium),
        );

    Widget arrow() => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Icon(Icons.arrow_forward, size: 14, color: cs.outline),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 折り返しても読めるよう Wrap で置く。端末の文字サイズが大きいと
        // 1行には収まらない。
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 6,
          runSpacing: 6,
          children: [
            node(l10n.guideFigureLoopSentence),
            arrow(),
            node(l10n.guideFigureLoopQuiz),
            // くり返しであることは記号だけでは伝わらないので、語を添える。
            Padding(
              padding: const EdgeInsets.only(left: 2),
              child: Icon(Icons.repeat, size: 14, color: cs.outline),
            ),
            Text(
              l10n.guideFigureLoopRepeat,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // 条件（例文5つごと）を先に置き、その結果としてまとめクイズが来る。
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 6,
          children: [
            Icon(Icons.subdirectory_arrow_right, size: 16, color: cs.outline),
            Text(
              l10n.guideFigureLoopEvery,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.gold.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                l10n.guideFigureLoopSummary,
                style: theme.textTheme.labelMedium
                    ?.copyWith(color: AppColors.goldInk),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// 例文カードの並びを示す図。深藍の面に3段、学習単語だけ金。
/// 実物と同じ配色にして、画面で見たときに同じものだと分かるようにする。
class GuideSentenceCardFigure extends StatelessWidget {
  const GuideSentenceCardFigure({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    Widget row(String caption, Widget sample) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: sample),
              const SizedBox(width: 10),
              SizedBox(
                width: 88,
                child: Text(
                  caption,
                  textAlign: TextAlign.right,
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
            ],
          ),
        );

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 10, 6),
      decoration: BoxDecoration(
        color: AppColors.indigo,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          row(
            l10n.guideFigureCardThai,
            Text.rich(
              TextSpan(
                children: [
                  const TextSpan(text: 'ผม '),
                  TextSpan(
                    text: 'ชอบ',
                    style: const TextStyle(color: AppColors.gold),
                  ),
                  const TextSpan(text: ' กาแฟ'),
                ],
                style: const TextStyle(color: Colors.white, fontSize: 20),
              ),
            ),
          ),
          row(
            l10n.guideFigureCardPronunciation,
            Text(
              'phǒm chɔ̂ɔp kaafɛɛ',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.72),
                fontSize: 13,
              ),
            ),
          ),
          row(
            l10n.guideFigureCardTranslation,
            Text(
              l10n.guideFigureCardTranslationSample,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.88),
                fontSize: 13,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(
                    color: AppColors.gold,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  l10n.guideFigureCardTargetWord,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.72),
                    fontSize: 12,
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

/// 発音判定の色の意味を示す図。実際の判定チップと同じ3色を並べる。
class GuideVerdictFigure extends StatelessWidget {
  const GuideVerdictFigure({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    Widget chip(Color color, String word, String label) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: color.withValues(alpha: 0.7)),
              ),
              child: Text(
                word,
                style: theme.textTheme.bodyMedium?.copyWith(color: color),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        );

    return Wrap(
      spacing: 14,
      runSpacing: 10,
      children: [
        chip(
          verdictColor(ToneVerdict.correct, cs),
          'ผม',
          l10n.pronunciationVerdictCorrect,
        ),
        chip(
          verdictColor(ToneVerdict.close, cs),
          'ชอบ',
          l10n.pronunciationVerdictClose,
        ),
        chip(
          verdictColor(ToneVerdict.wrong, cs),
          'กาแฟ',
          l10n.pronunciationVerdictWrong,
        ),
      ],
    );
  }
}

/// 例文の下に出る確認クイズの導線を、実物と同じ翡翠の枠で見せる図。
/// 「例文の下の導線」がどれを指すのか、文だけでは分からない。
class GuideQuizOfferFigure extends StatelessWidget {
  const GuideQuizOfferFigure({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.jade),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_rounded, size: 20, color: AppColors.jade),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.quizOfferOneQuestion,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.jade,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  l10n.quizOfferBody,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.chevron_right, size: 20, color: AppColors.jade),
        ],
      ),
    );
  }
}

/// 無料版とプレミアムの差を並べた比較表。
///
/// 文章で「無料は5文、プレミアムは20文」と書くと、項目が増えるほど
/// どちらの話か追えなくなる。列を固定して縦に読ませる。
/// プレミアム側の列だけ金で沈めて、増える側がひと目で分かるようにする。
class GuidePlanCompareFigure extends StatelessWidget {
  const GuidePlanCompareFigure({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final headerStyle = theme.textTheme.labelMedium?.copyWith(
      color: cs.onSurfaceVariant,
      fontWeight: FontWeight.w700,
    );
    final itemStyle = theme.textTheme.bodySmall?.copyWith(
      color: cs.onSurfaceVariant,
    );
    final freeStyle = theme.textTheme.bodySmall;
    final premiumStyle = theme.textTheme.bodySmall?.copyWith(
      fontWeight: FontWeight.w700,
      color: AppColors.goldInk,
    );

    TableRow row(String item, String free, String premium, TextStyle? style) {
      return TableRow(
        children: [
          _cell(Text(item, style: itemStyle)),
          _cell(Text(free, style: style ?? freeStyle)),
          _cell(Text(premium, style: style ?? premiumStyle)),
        ],
      );
    }

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: cs.outlineVariant),
        borderRadius: BorderRadius.circular(10),
      ),
      clipBehavior: Clip.antiAlias,
      child: Table(
        // 項目名は語数が読めるので広く、値の2列は等分にする。
        columnWidths: const {
          0: FlexColumnWidth(1.2),
          1: FlexColumnWidth(1),
          2: FlexColumnWidth(1),
        },
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        border: TableBorder.symmetric(
          inside: BorderSide(color: cs.outlineVariant),
        ),
        children: [
          TableRow(
            decoration: BoxDecoration(color: cs.surfaceContainerHighest),
            children: [
              _cell(Text(l10n.guidePlanColItem, style: headerStyle)),
              _cell(Text(l10n.guidePlanColFree, style: headerStyle)),
              _cell(Text(
                l10n.guidePlanColPremium,
                style: headerStyle?.copyWith(color: AppColors.goldInk),
              )),
            ],
          ),
          row(
            l10n.guidePlanRowSentences,
            l10n.guidePlanSentences(freeDailySentences),
            l10n.guidePlanSentences(premiumDailySentences),
            null,
          ),
          row(
            l10n.guidePlanRowTopic,
            l10n.guidePlanTopicFree,
            l10n.guidePlanTopicPremium,
            null,
          ),
          row(
            l10n.guidePlanRowVocab,
            l10n.guidePlanVocabFree(freeVocabScoreLimit),
            l10n.guidePlanVocabPremium(premiumVocabScoreGuide),
            null,
          ),
        ],
      ),
    );
  }

  static Widget _cell(Widget child) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        child: child,
      );
}
