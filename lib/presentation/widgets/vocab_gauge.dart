// =============================================================================
// vocab_gauge.dart
// 語の覚え具合のゲージと、状態ごとの色・文言。
// =============================================================================

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../data/models/vocab_word.dart';
import '../../l10n/app_localizations.dart';

extension VocabMasteryStyle on VocabMastery {
  String label(L10n l10n) => switch (this) {
        VocabMastery.seen => l10n.vocabMasterySeen,
        VocabMastery.learning => l10n.vocabMasteryLearning,
        VocabMastery.learned => l10n.vocabMasteryLearned,
      };

  /// 文字に使う色。
  Color inkColor(BuildContext context) {
    final theme = Theme.of(context);
    return switch (this) {
      VocabMastery.seen => theme.colorScheme.onSurfaceVariant,
      VocabMastery.learning => theme.brightness == Brightness.dark
          ? AppColors.gold
          : AppColors.goldInk,
      VocabMastery.learned => AppColors.jade,
    };
  }
}

/// 覚え具合のゲージ。覚えた語は緑、それ以外は金、未回答は空。
class VocabGauge extends StatelessWidget {
  final VocabWord word;
  final double? width;

  const VocabGauge({super.key, required this.word, this.width = 72});

  @override
  Widget build(BuildContext context) {
    final fill =
        word.mastery == VocabMastery.learned ? AppColors.jade : AppColors.gold;
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        width: width,
        height: 8,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: Theme.of(context).colorScheme.surfaceContainerHigh),
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: word.gauge,
              child: ColoredBox(color: fill),
            ),
          ],
        ),
      ),
    );
  }
}
