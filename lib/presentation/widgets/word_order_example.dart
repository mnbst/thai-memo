import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// 例文1つ。語ごとにタイ文字・読み・意味を並べ、その項目で見てほしい語を
/// [focus] で色付きにする。意味は `|` 区切りで語と同じ数だけ持つ。
class WordOrderExample {
  final List<String> words;
  final List<String> readings;
  final Set<int> focus;
  final String Function(L10n) gloss;
  final String Function(L10n) meaning;

  const WordOrderExample(
    this.words,
    this.readings,
    this.focus,
    this.gloss,
    this.meaning,
  );
}

/// 例文を語のチップで左から並べ、下に訳を出す。
class WordOrderExampleView extends StatelessWidget {
  final WordOrderExample example;

  const WordOrderExampleView({super.key, required this.example});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    final glosses = example.gloss(l10n).split('|');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final (i, word) in example.words.indexed)
                _WordChip(
                  word: word,
                  reading: example.readings[i],
                  gloss: i < glosses.length ? glosses[i] : '',
                  focused: example.focus.contains(i),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            example.meaning(l10n),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _WordChip extends StatelessWidget {
  final String word;
  final String reading;
  final String gloss;
  final bool focused;

  const _WordChip({
    required this.word,
    required this.reading,
    required this.gloss,
    required this.focused,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final foreground = focused ? scheme.onPrimaryContainer : scheme.onSurface;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: focused ? scheme.primaryContainer : scheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: focused ? scheme.primary : scheme.outlineVariant,
          width: focused ? 1.5 : 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            word,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: foreground,
            ),
          ),
          Text(
            reading,
            style: theme.textTheme.bodySmall?.copyWith(
              color: focused ? foreground : scheme.onSurfaceVariant,
            ),
          ),
          Text(
            gloss,
            style: theme.textTheme.bodySmall?.copyWith(color: foreground),
          ),
        ],
      ),
    );
  }
}
