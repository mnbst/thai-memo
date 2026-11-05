// =============================================================================
// vocab_guide_card.dart
// 復習タブの上に、閉じるまで出す案内。見た目は例文詳細の案内
// （DetailGuideCard）にそろえる。
// =============================================================================

import 'package:flutter/material.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/app_colors.dart';
import '../../l10n/app_localizations.dart';

class VocabGuideCard extends StatelessWidget {
  const VocabGuideCard({super.key, required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final hintStyle =
        theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant);
    // 文中に AppBar と同じアイコンを埋める。語順は言語ごとに違うので文言側で位置を決める。
    const iconMark = '\uFFFC';
    final tapHint = l10n.vocabGuideTapWordHint(iconMark).split(iconMark);
    final items = <(IconData, String, Widget)>[
      (
        Icons.touch_app_outlined,
        l10n.vocabGuideTapWord,
        Text.rich(
          TextSpan(children: [
            TextSpan(text: tapHint.first),
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Icon(
                  Icons.article_outlined,
                  size: 16,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
            TextSpan(text: tapHint.last),
          ]),
          style: hintStyle,
        ),
      ),
      (
        Icons.linear_scale_rounded,
        l10n.vocabGuideMeaning,
        Text(l10n.vocabGuideMeaningHint, style: hintStyle),
      ),
      (
        Icons.quiz_outlined,
        l10n.vocabGuideQuiz,
        Text(
          '${l10n.vocabGuideQuizHint}\n${l10n.vocabGuideRangeHint}',
          style: hintStyle,
        ),
      ),
    ];
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppConfig.cardBorderRadius),
        side: BorderSide(color: cs.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 2, 4, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.vocabGuideTitle,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  color: cs.onSurfaceVariant,
                  tooltip: l10n.commonClose,
                  visualDensity: VisualDensity.compact,
                  onPressed: onClose,
                ),
              ],
            ),
            for (final (icon, label, hint) in items)
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 4, 10, 4),
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
                          hint,
                        ],
                      ),
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
