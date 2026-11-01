import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/app_colors.dart';
import '../../l10n/app_localizations.dart';
import '../providers/analytics_provider.dart';
import 'first_set_steps.dart';

/// 例文詳細を初めて開いた人に「この画面でできること」を並べる案内。
///
/// 学習タブの手順カード（FirstSetSteps）と見た目はそろえるが、こちらは
/// やらなくても進める寄り道なので番号とチェックは付けず、アイコンで並べる。
/// 最後に学習へ戻る導線を置き、確認クイズから遠ざけない。
///
/// 出すのは最初の例文（firstSentenceIdProvider）の詳細だけ。開くたびに出し、
/// ×は置かない。

enum DetailGuideItem { practice, usage, words }

class DetailGuideCard extends ConsumerStatefulWidget {
  const DetailGuideCard({
    super.key,
    required this.sentenceId,
    this.onItemTap,
    this.onBackToLearn,
  });

  final String? sentenceId;

  /// 項目を押したとき。その場所までスクロールする想定。
  final ValueChanged<DetailGuideItem>? onItemTap;

  /// 「学習に戻って確認クイズを解く」。
  final VoidCallback? onBackToLearn;

  @override
  ConsumerState<DetailGuideCard> createState() => _DetailGuideCardState();
}

class _DetailGuideCardState extends ConsumerState<DetailGuideCard> {
  bool _shownLogged = false;

  void _log(String action) => unawaited(ref
      .read(analyticsServiceProvider)
      .logCoachMark(id: 'detail_guide', action: action));

  @override
  Widget build(BuildContext context) {
    if (!isFirstSentence(ref, widget.sentenceId)) {
      return const SizedBox.shrink();
    }
    if (!_shownLogged) {
      _shownLogged = true;
      _log('shown');
    }
    final onItemTap = widget.onItemTap;

    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final items = [
      (
        DetailGuideItem.practice,
        Icons.mic_none_rounded,
        l10n.detailGuidePractice,
        l10n.detailGuidePracticeHint
      ),
      // 並びは詳細画面の上からの順（発音 → 使い方 → 単語）。
      (
        DetailGuideItem.usage,
        Icons.lightbulb_outline_rounded,
        l10n.detailGuideUsage,
        l10n.detailGuideUsageHint
      ),
      (
        DetailGuideItem.words,
        Icons.translate_rounded,
        l10n.detailGuideWords,
        l10n.detailGuideWordsHint
      ),
    ];

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppConfig.cardBorderRadius),
        side: BorderSide(color: cs.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 6, 4, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 6, 10, 2),
              child: Text(
                l10n.detailGuideTitle,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            for (final (item, icon, label, hint) in items)
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: onItemTap == null
                    ? null
                    : () {
                        _log(item.name);
                        onItemTap(item);
                      },
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(0, 6, 10, 6),
                  child: Row(
                    children: [
                      Icon(icon, size: 22, color: AppColors.jade),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              label,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              hint,
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: cs.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right,
                          size: 18, color: cs.onSurfaceVariant),
                    ],
                  ),
                ),
              ),
            Divider(height: 12, color: cs.outlineVariant),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: widget.onBackToLearn == null
                    ? null
                    : () {
                        _log('back_to_learn');
                        widget.onBackToLearn!();
                      },
                style: TextButton.styleFrom(foregroundColor: AppColors.jade),
                icon: const Icon(Icons.arrow_back_rounded, size: 18),
                label: Text(l10n.detailGuideBackToQuiz),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
