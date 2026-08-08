import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';

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

    return Card(
      key: const ValueKey('quiz_offer_inline_v1'),
      color: colors.primaryContainer.withValues(alpha: 0.55),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.bolt_rounded, color: colors.primary),
                const SizedBox(width: 8),
                // 英語の見出しは日本語より長く、狭い端末で横にあふれる。
                Expanded(
                  child: Text(
                    L10n.of(context).quizOfferOneQuestion,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              L10n.of(context).quizOfferBody,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            _buildButton(context, L10n.of(context).quizOfferTryOne),
          ],
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
