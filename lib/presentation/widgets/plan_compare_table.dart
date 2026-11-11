// =============================================================================
// plan_compare_table.dart
// 無料版とプレミアムの比較表。使い方ガイドとペイウォールで共通に使う。
// =============================================================================

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../l10n/app_localizations.dart';
import '../providers/pronunciation_provider.dart';
import '../screens/paywall_screen.dart';
import 'vocab_level.dart';

/// 無料版とプレミアムの差を並べた比較表。
///
/// 文章で「無料は2セット、プレミアムは無制限」と書くと、項目が増えるほど
/// どちらの話か追えなくなる。列を固定して縦に読ませる。
/// プレミアム側の列だけ金で沈めて、増える側がひと目で分かるようにする。
///
/// 使い方ガイドとペイウォールで同じものを出す。どちらもカードと同じ白地。
class PlanCompareTable extends StatelessWidget {
  const PlanCompareTable({super.key});

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
        color: cs.surface,
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
              // 項目列の見出しは置かない。行の名前で何の比較か分かる。
              const SizedBox.shrink(),
              _cell(Text(l10n.guidePlanColFree, style: headerStyle)),
              _cell(Text(
                l10n.guidePlanColPremium,
                style: headerStyle?.copyWith(color: AppColors.goldInk),
              )),
            ],
          ),
          row(
            l10n.guidePlanRowSentences,
            l10n.guidePlanSentences(freeDailySets),
            l10n.guidePlanSentencesUnlimited,
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
            l10n.guidePlanVocabUnlimited,
            null,
          ),
          row(
            l10n.guidePlanRowPronunciation,
            l10n.guidePlanPronunciationFree(freePronunciationDailyLimit),
            l10n.guidePlanPronunciationUnlimited,
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
