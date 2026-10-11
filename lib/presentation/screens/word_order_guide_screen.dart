import 'package:flutter/material.dart';

import '../../core/config/app_config.dart';
import '../../l10n/app_localizations.dart';
import '../widgets/swipe_back.dart';

/// タイ語の語順ガイド画面。並び替え問題の補助として、設定と解答画面から開く。
class WordOrderGuideScreen extends StatelessWidget {
  static const routeName = 'word_order_guide';

  const WordOrderGuideScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final rules = [
      (l10n.wordOrderRule1Title, l10n.wordOrderRule1Body),
      (l10n.wordOrderRule2Title, l10n.wordOrderRule2Body),
      (l10n.wordOrderRule3Title, l10n.wordOrderRule3Body),
      (l10n.wordOrderRule4Title, l10n.wordOrderRule4Body),
      (l10n.wordOrderRule5Title, l10n.wordOrderRule5Body),
      (l10n.wordOrderRule6Title, l10n.wordOrderRule6Body),
      (l10n.wordOrderRule7Title, l10n.wordOrderRule7Body),
      (l10n.wordOrderRule8Title, l10n.wordOrderRule8Body),
      (l10n.wordOrderRule9Title, l10n.wordOrderRule9Body),
      (l10n.wordOrderRule10Title, l10n.wordOrderRule10Body),
    ];

    return Scaffold(
      appBar: AppBar(title: Text(l10n.wordOrderGuideTitle)),
      body: SwipeBack(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppConfig.defaultPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _IntroCard(
                heading: l10n.wordOrderGuideHeading,
                body: l10n.wordOrderGuideIntro,
              ),
              const SizedBox(height: 16),
              for (final (i, (title, body)) in rules.indexed) ...[
                _RuleCard(number: i + 1, title: title, body: body),
                const SizedBox(height: 12),
              ],
              const SizedBox(height: 12),
              _RuleCard(
                icon: Icons.lightbulb_outline,
                title: l10n.wordOrderTipsTitle,
                body: l10n.wordOrderTipsBody,
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

class _IntroCard extends StatelessWidget {
  final String heading;
  final String body;

  const _IntroCard({required this.heading, required this.body});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onColor = theme.colorScheme.onPrimaryContainer;
    return Card(
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(AppConfig.defaultPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline, color: onColor, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    heading,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: onColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              body,
              style: theme.textTheme.bodyMedium?.copyWith(color: onColor),
            ),
          ],
        ),
      ),
    );
  }
}

class _RuleCard extends StatelessWidget {
  final int? number;
  final IconData? icon;
  final String title;
  final String body;

  const _RuleCard({
    this.number,
    this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppConfig.defaultPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (number != null)
                  CircleAvatar(
                    radius: 12,
                    backgroundColor: primary,
                    child: Text(
                      '$number',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onPrimary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  )
                else if (icon != null)
                  Icon(icon, color: primary, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(body,
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.6)),
          ],
        ),
      ),
    );
  }
}
