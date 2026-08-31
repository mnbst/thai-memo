import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/app_colors.dart';
import '../providers/quiz_offer_experiment_provider.dart';

/// 例文から1問確認クイズへ進むA/Bテスト用の導線。
///
/// 配置（下部固定か例文直下か）は親が決め、このWidgetは各variantの見た目だけを
/// 担う。実際に描画されたボタンへ初回ガイドを付けられるよう[targetKey]を受け取る。
class QuizOffer extends StatelessWidget {
  const QuizOffer({
    super.key,
    required this.variant,
    required this.targetKey,
    required this.onPressed,
  });

  final QuizOfferVariant variant;
  final GlobalKey targetKey;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return switch (variant) {
      QuizOfferVariant.controlBottom ||
      QuizOfferVariant.unassignedControl =>
        KeyedSubtree(
          key: const ValueKey('quiz_offer_control_v1'),
          child: _buildButton(context, L10n.of(context).quizOfferToQuiz),
        ),
      QuizOfferVariant.inlineOneQuestion => _buildInlineCard(context),
    };
  }

  Widget _buildInlineCard(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    // 例文カード（深藍）・学習単語カード（白）と並ぶので、面ではなく
    // 翡翠の細い罫線で「まだ済んでいない次の一手」だと示す。
    //
    // 中にボタンは置かない。枠の中にもう一段ボタンがあると、押す場所が
    // 二重になって的が絞れない。カード全体を1つのタップ領域にする。
    return KeyedSubtree(
      key: targetKey,
      child: Card(
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConfig.cardBorderRadius),
          side: const BorderSide(color: AppColors.jade),
        ),
        child: InkWell(
          key: const ValueKey('quiz_offer_inline_v1'),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
            child: Row(
              children: [
                const Icon(Icons.check_rounded,
                    size: 20, color: AppColors.jade),
                const SizedBox(width: 12),
                // 英語の見出しは日本語より長く、狭い端末で横にあふれる。
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        L10n.of(context).quizOfferOneQuestion,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: AppColors.jade,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        L10n.of(context).quizOfferBody,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: colors.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right,
                    size: 20, color: AppColors.jade),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildButton(BuildContext context, String label) {
    return KeyedSubtree(
      key: targetKey,
      child: FilledButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.quiz),
        label: Text(label),
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
          minimumSize: const Size.fromHeight(56),
        ),
      ),
    );
  }
}
