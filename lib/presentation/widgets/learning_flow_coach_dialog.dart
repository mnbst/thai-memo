import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// 学習の流れ（例文 → クイズ → 例文 → クイズ → … → 5問クイズ）を教える案内。
///
/// スポットライトではなく中央のダイアログで出す。指す対象が画面の一部ではなく
/// 「くり返しそのもの」なので、光らせる場所が無い。
///
/// 話すのはくり返しの形だけ。5問クイズの解き方は、実際に解いた直後に
/// [SummaryQuizTipsDialog] で出す（まだ解いていない時点では実感が無い）。
///
/// 機能紹介の締めくくりを読んだ直後、例文画面へ戻った1回だけ出す。
class LearningFlowCoachDialog extends StatefulWidget {
  const LearningFlowCoachDialog({super.key});

  /// 出して、閉じられるまで待つ。
  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const LearningFlowCoachDialog(),
    );
  }

  @override
  State<LearningFlowCoachDialog> createState() =>
      _LearningFlowCoachDialogState();
}

class _LearningFlowCoachDialogState extends State<LearningFlowCoachDialog> {
  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);

    return AlertDialog(
      icon: Icon(
        Icons.map_outlined,
        color: theme.colorScheme.primary,
        size: 32,
      ),
      title: Text(l10n.coachFlowTitle),
      content: const _LoopPage(),
      // 端末の文字サイズを大きくしている場合でも溢れないようにする。
      scrollable: true,
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.coachFlowContinue),
        ),
      ],
    );
  }
}

/// 本文。例文とクイズのくり返しを図で見せる。
class _LoopPage extends StatelessWidget {
  const _LoopPage();

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 機能紹介の締めくくりから続けて出る画面。まずねぎらってから本題に入る。
        Text(
          l10n.coachFlowGreeting,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 14),
        _PageTitle(
          icon: Icons.repeat,
          text: l10n.coachFlowPage1Title,
        ),
        const SizedBox(height: 12),
        const _LoopDiagram(),
        const SizedBox(height: 14),
        // くり返しの形だけだと「何のために」が残らない。この輪を回した先に
        // 何が起きるのかを一行で置く。
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.trending_up,
              size: 16,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                l10n.coachFlowOutcome,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// ページの見出し。アイコンと1行。
class _PageTitle extends StatelessWidget {
  const _PageTitle({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Icon(icon, size: 20, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

/// 例文 → クイズ → 例文 → クイズ → … → 5問クイズ のくり返しを見せる図。
///
/// 最後の「5問クイズ」まで同じ並びに置く。次のページで話す5問クイズが、
/// くり返しの先にあることが図のまま伝わる。
class _LoopDiagram extends StatelessWidget {
  const _LoopDiagram();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);

    Widget chip(String label, {required Color background, required Color fore}) =>
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: fore,
              fontWeight: FontWeight.w600,
            ),
          ),
        );

    Widget sentence() => chip(
          l10n.coachFlowLoopSentence,
          background: theme.colorScheme.primaryContainer,
          fore: theme.colorScheme.onPrimaryContainer,
        );

    Widget quiz() => chip(
          l10n.coachFlowLoopQuiz,
          background: theme.colorScheme.secondaryContainer,
          fore: theme.colorScheme.onSecondaryContainer,
        );

    Widget arrow() => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Icon(
            Icons.arrow_forward,
            size: 14,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        );

    Widget dots() => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            '…',
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        );

    // 端末の文字サイズによっては1行に収まらない。折り返して切れないようにする。
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      runSpacing: 6,
      children: [
        sentence(),
        arrow(),
        quiz(),
        arrow(),
        sentence(),
        arrow(),
        quiz(),
        dots(),
        arrow(),
        chip(
          l10n.coachFlowLoopSummary,
          background: theme.colorScheme.primary,
          fore: theme.colorScheme.onPrimary,
        ),
      ],
    );
  }
}
