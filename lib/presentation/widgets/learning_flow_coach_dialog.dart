import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// 学習の流れ（例文 → クイズ → 例文 → クイズ → … → 5問クイズ）を教える案内。
///
/// スポットライトではなく中央のダイアログで出す。指す対象が画面の一部ではなく
/// 「くり返しそのもの」なので、光らせる場所が無い。
///
/// 2ページに分ける。1ページ目は例文とクイズのくり返し（図で見せる）、
/// 2ページ目はその先にある5問クイズの解き方。1枚に詰めると、くり返しの図と
/// 解き方の話が同じ重さで並んでどちらも読まれない。
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
  int _page = 0;

  static const _pageCount = 2;

  void _next() {
    if (_page >= _pageCount - 1) {
      Navigator.pop(context);
      return;
    }
    setState(() => _page += 1);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    final isLast = _page == _pageCount - 1;

    return AlertDialog(
      icon: Icon(
        Icons.map_outlined,
        color: theme.colorScheme.primary,
        size: 32,
      ),
      title: Text(l10n.coachFlowTitle),
      // ページを差し替えて出す。PageView のように高さを決め打ちすると、
      // 短いページで下に大きな余白が残る。
      content: AnimatedSize(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        alignment: Alignment.topCenter,
        child: _page == 0
            ? _LoopPage(key: const ValueKey('flow_page_0'))
            : _SummaryQuizPage(key: const ValueKey('flow_page_1')),
      ),
      // 端末の文字サイズを大きくしている場合でも溢れないようにする。
      scrollable: true,
      actions: [
        Row(
          children: [
            Text(
              l10n.coachFlowStepLabel(_page + 1, _pageCount),
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const Spacer(),
            FilledButton(
              onPressed: _next,
              child: Text(isLast ? l10n.coachFlowStart : l10n.coachFlowNext),
            ),
          ],
        ),
      ],
    );
  }
}

/// 1ページ目。例文とクイズのくり返しを図で見せる。
class _LoopPage extends StatelessWidget {
  const _LoopPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PageTitle(
          icon: Icons.repeat,
          text: l10n.coachFlowPage1Title,
        ),
        const SizedBox(height: 12),
        const _LoopDiagram(),
        const SizedBox(height: 14),
        _EmphasizedText(
          text: l10n.coachFlowBody1,
          emphasis: l10n.coachFlowBody1Emphasis,
          style: theme.textTheme.bodyMedium,
        ),
      ],
    );
  }
}

/// 2ページ目。くり返しの先にある5問クイズと、その解き方。
class _SummaryQuizPage extends StatelessWidget {
  const _SummaryQuizPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PageTitle(
          icon: Icons.emoji_events_outlined,
          text: l10n.coachFlowPage2Title,
        ),
        const SizedBox(height: 12),
        _Bullet(
          text: l10n.coachFlowPage2Bullet1,
          emphasis: l10n.coachFlowPage2Bullet1Emphasis,
        ),
        _Bullet(
          text: l10n.coachFlowPage2Bullet2,
          emphasis: l10n.coachFlowPage2Bullet2Emphasis,
        ),
      ],
    );
  }
}

/// 箇条書きの1行。要点だけ色を変えて、拾い読みでも残るようにする。
class _Bullet extends StatelessWidget {
  const _Bullet({required this.text, this.emphasis});

  final String text;
  final String? emphasis;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6, right: 8),
            child: Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                shape: BoxShape.circle,
              ),
            ),
          ),
          Expanded(
            child: _EmphasizedText(
              text: text,
              emphasis: emphasis,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
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

/// 本文中の一部だけを強調して描く。初回ガイドの吹き出しと同じ見せ方に揃える。
///
/// [emphasis] が本文に含まれない場合（訳の揺れ）はそのまま描く。強調が
/// 消えるだけで、文が欠けることはない。
class _EmphasizedText extends StatelessWidget {
  const _EmphasizedText({
    required this.text,
    required this.style,
    this.emphasis,
  });

  final String text;
  final String? emphasis;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final target = emphasis;
    if (target == null || target.isEmpty) return Text(text, style: style);
    final start = text.indexOf(target);
    if (start < 0) return Text(text, style: style);

    return Text.rich(
      TextSpan(
        style: style,
        children: [
          TextSpan(text: text.substring(0, start)),
          TextSpan(
            text: target,
            style: TextStyle(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
          TextSpan(text: text.substring(start + target.length)),
        ],
      ),
    );
  }
}
