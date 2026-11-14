// =============================================================================
// learning_flow_steps.dart
// 学習の流れ3段（例文を読む → 確認クイズ → まとめクイズ）。番号の丸と縦線で
// つなぎ、各段は見出し一言＋実物と同じ見た目の図＋添え書き。
// 初回の簡易ガイド（QuickGuideScreen）と使い方ガイドの「概要」で共用する。
// =============================================================================

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import 'guide_figures.dart';

class LearningFlowSteps extends StatelessWidget {
  const LearningFlowSteps({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final steps = <(String, Widget)>[
      (
        l10n.quickGuideStepRead,
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const GuideSentenceCardFigure(),
            const SizedBox(height: 10),
            // 声調チェック・綴りの確認は使っても使わなくてもよいので、段に
            // せず例文の下に添える。
            _Option(icon: Icons.mic_none, text: l10n.quickGuideOptSpeak),
            _Option(icon: Icons.spellcheck, text: l10n.quickGuideOptSpelling),
          ],
        ),
      ),
      // 例文ごとの確認クイズではスコアは動かない。動くのはまとめクイズだけ。
      (
        l10n.quickGuideStepCheck,
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const GuideQuizOfferFigure(),
            const SizedBox(height: 10),
            _Option(
              icon: Icons.menu_book_outlined,
              text: l10n.quickGuideOptReview(l10n.navHistory),
            ),
          ],
        ),
      ),
      (l10n.quickGuideStepQuiz, const _SummaryFigure()),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, (caption, figure)) in steps.indexed)
          _Step(
            number: i + 1,
            caption: caption,
            figure: figure,
            isLast: i == steps.length - 1,
          ),
      ],
    );
  }
}

/// 番号の丸と縦線でつないだ1段。見出しは一言、中身は図。
class _Step extends StatelessWidget {
  const _Step({
    required this.number,
    required this.caption,
    required this.figure,
    required this.isLast,
  });

  final int number;
  final String caption;
  final Widget figure;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    // 縦線は Stack で段の高さいっぱいに引く。IntrinsicHeight で測ると、
    // FittedBox で縮めた図の高さが縮める前の値になり、空白が残る。
    return Stack(
      children: [
        if (!isLast)
          Positioned(
            left: 15,
            top: 32,
            bottom: 4,
            child: Container(width: 2, color: cs.outlineVariant),
          ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              child: Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: cs.primary,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '$number',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: cs.onPrimary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(bottom: isLast ? 0 : 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 5, bottom: 8),
                      child: Text(
                        caption,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                    figure,
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// 例文の下に添える、使っても使わなくてもよい機能の1行。
class _Option extends StatelessWidget {
  const _Option({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: cs.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

/// まとめクイズの添え書き。スコアに合った例文が出ることと、出るタイミング。
class _SummaryFigure extends StatelessWidget {
  const _SummaryFigure();

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Option(icon: Icons.trending_up, text: l10n.quickGuideNextSentences),
        _Option(icon: Icons.repeat, text: l10n.quickGuideOptSummaryEvery),
      ],
    );
  }
}
