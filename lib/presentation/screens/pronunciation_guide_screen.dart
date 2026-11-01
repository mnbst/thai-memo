import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../core/constants/pronunciation_guide_sections.dart';
import '../../l10n/app_localizations.dart';
import '../providers/analytics_provider.dart';
import '../providers/tts_provider.dart';
import '../widgets/swipe_back.dart';

/// 読みの記号の一覧。説明は pronSymbolsDescs を `|` で区切って同じ順に引く。
const _symbols = [
  'ɛ  ɔ',
  'ʉ',
  'ə',
  'aa  ii',
  'k  kh',
  'th  ph',
  'ng',
  'à  â  á  ǎ'
];

/// タイ語の発音ガイド画面。読みの記号と、日本語話者が区別しにくい音をまとめる。
/// 声調は声調ガイドに任せる。
class PronunciationGuideScreen extends StatelessWidget {
  static const routeName = 'pronunciation_guide';

  const PronunciationGuideScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.pronGuideTitle)),
      body: SwipeBack(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppConfig.defaultPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _IntroCard(
                heading: l10n.pronGuideHeading,
                body: l10n.pronGuideIntro,
              ),
              const SizedBox(height: 16),
              const _SymbolsCard(),
              for (final section in pronunciationSections) ...[
                const SizedBox(height: 12),
                _SectionCard(section: section),
              ],
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

class _CardTitle extends StatelessWidget {
  final IconData icon;
  final String title;

  const _CardTitle(this.icon, this.title);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, color: theme.colorScheme.primary, size: 22),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}

/// 読みの記号と、その音の説明を表にする。
class _SymbolsCard extends StatelessWidget {
  const _SymbolsCard();

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    final descs = l10n.pronSymbolsDescs.split('|');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppConfig.defaultPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _CardTitle(Icons.abc, l10n.pronSymbolsTitle),
            const SizedBox(height: 8),
            Text(l10n.pronSymbolsBody, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 8),
            for (final (i, symbol) in _symbols.indexed) ...[
              if (i > 0) const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 92,
                      child: Text(
                        symbol,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        i < descs.length ? descs[i] : '',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final PronSection section;

  const _SectionCard({required this.section});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    final meanings = section.meanings?.call(l10n).split('|') ?? const [];
    final note = section.note?.call(l10n);
    var index = 0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppConfig.defaultPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _CardTitle(section.icon, section.title(l10n)),
            const SizedBox(height: 8),
            Text(section.body(l10n), style: theme.textTheme.bodyMedium),
            for (final row in section.rows) ...[
              const SizedBox(height: 10),
              _ExampleRow(
                row: row,
                meanings: [
                  for (var i = 0; i < row.words.length; i++)
                    index < meanings.length ? meanings[index++] : '',
                ],
              ),
            ],
            if (note != null) ...[
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline,
                      size: 16, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      note,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ExampleRow extends StatelessWidget {
  final PronRow row;
  final List<String> meanings;

  const _ExampleRow({required this.row, required this.meanings});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tiles = [
      for (final (i, word) in row.words.indexed)
        Expanded(child: _WordTile(word: word, meaning: meanings[i])),
    ];
    return Row(
      children: [
        for (final (i, tile) in tiles.indexed) ...[
          if (i > 0)
            row.contrast
                ? Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Icon(Icons.swap_horiz,
                        size: 18, color: theme.colorScheme.outline),
                  )
                : const SizedBox(width: 8),
          tile,
        ],
      ],
    );
  }
}

/// 語1つ。タイ文字・読み・意味を縦に積む。崩れた読みがあれば「読み → 崩れ」。
/// 札全体を押すとその語を読み上げる。
class _WordTile extends ConsumerWidget {
  final PronWord word;
  final String meaning;

  const _WordTile({required this.word, required this.meaning});

  void _speak(WidgetRef ref) {
    unawaited(
      ref.read(analyticsServiceProvider).logPlayTts(
            contentType: 'word',
            text: word.thai,
            source: 'pronunciation_guide',
          ),
    );
    // 比べる2語を同じ声で聞き比べられるよう、話者を変えない。
    // 長短の違いを聞かせたいので、ゆっくり読みにはしない。
    unawaited(ref.read(ttsServiceProvider).speak(word.thai, keepVoice: true));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final readingStyle = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.primary,
      fontWeight: FontWeight.w600,
    );
    final spoken = word.spoken;
    final thaiText = Text(word.thai,
        style: theme.textTheme.titleLarge?.copyWith(fontSize: 24, height: 1.3));
    final speaker = Icon(Icons.volume_up_outlined,
        size: 18, color: theme.colorScheme.primary);
    final reading = spoken == null
        ? Text(word.reading, style: readingStyle)
        : Text.rich(TextSpan(style: readingStyle, children: [
            TextSpan(
              text: word.reading,
              style: TextStyle(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.normal,
              ),
            ),
            const TextSpan(text: '  →  '),
            TextSpan(text: spoken),
          ]));
    final meaningText = Text(
      meaning,
      style: theme.textTheme.bodySmall
          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
    );
    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _speak(ref),
        child: Semantics(
          button: true,
          label: L10n.of(context).playPronunciation,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            // 崩れの行は語が1つなので横に並べ、比べる行は縦に積む。
            child: spoken == null
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(child: thaiText),
                          speaker,
                        ],
                      ),
                      reading,
                      meaningText,
                    ],
                  )
                : Row(
                    children: [
                      thaiText,
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [reading, meaningText],
                        ),
                      ),
                      speaker,
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
