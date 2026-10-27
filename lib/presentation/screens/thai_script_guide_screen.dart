import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../l10n/app_localizations.dart';
import '../providers/analytics_provider.dart';
import '../providers/tts_provider.dart';
import '../widgets/swipe_back.dart';
import 'tone_guide_screen.dart';

enum _LetterClass { middle, high, low }

class _Consonant {
  final String letter;
  final String name;
  final String spokenName;
  final String initial;
  final String finalSound;
  final _LetterClass letterClass;

  const _Consonant(
    this.letter,
    this.name,
    this.spokenName,
    this.initial,
    this.finalSound,
    this.letterClass,
  );
}

const _consonants = [
  _Consonant('ก', 'kɔɔ kài', 'กอ ไก่', 'k', 'k', _LetterClass.middle),
  _Consonant('ข', 'khɔ̌ɔ khài', 'ขอ ไข่', 'kh', 'k', _LetterClass.high),
  _Consonant('ค', 'khɔɔ khwaai', 'คอ ควาย', 'kh', 'k', _LetterClass.low),
  _Consonant('ง', 'ngɔɔ nguu', 'งอ งู', 'ng', 'ng', _LetterClass.low),
  _Consonant('จ', 'jɔɔ jaan', 'จอ จาน', 'j', 't', _LetterClass.middle),
  _Consonant('ช', 'chɔɔ cháang', 'ชอ ช้าง', 'ch', 't', _LetterClass.low),
  _Consonant('ด', 'dɔɔ dèk', 'ดอ เด็ก', 'd', 't', _LetterClass.middle),
  _Consonant('ต', 'tɔɔ tàw', 'ตอ เต่า', 't', 't', _LetterClass.middle),
  _Consonant('ท', 'thɔɔ thá-hǎan', 'ทอ ทหาร', 'th', 't', _LetterClass.low),
  _Consonant('น', 'nɔɔ nǔu', 'นอ หนู', 'n', 'n', _LetterClass.low),
  _Consonant('บ', 'bɔɔ bai mái', 'บอ ใบไม้', 'b', 'p', _LetterClass.middle),
  _Consonant('ป', 'pɔɔ plaa', 'ปอ ปลา', 'p', 'p', _LetterClass.middle),
  _Consonant('พ', 'phɔɔ phaan', 'พอ พาน', 'ph', 'p', _LetterClass.low),
  _Consonant('ม', 'mɔɔ máa', 'มอ ม้า', 'm', 'm', _LetterClass.low),
  _Consonant('ย', 'yɔɔ yák', 'ยอ ยักษ์', 'y', 'y', _LetterClass.low),
  _Consonant('ร', 'rɔɔ rʉa', 'รอ เรือ', 'r', 'n', _LetterClass.low),
  _Consonant('ล', 'lɔɔ ling', 'ลอ ลิง', 'l', 'n', _LetterClass.low),
  _Consonant('ว', 'wɔɔ wɛ̌ɛn', 'วอ แหวน', 'w', 'w', _LetterClass.low),
  _Consonant('ส', 'sɔ̌ɔ sʉ̌a', 'สอ เสือ', 's', 't', _LetterClass.high),
  _Consonant('ห', 'hɔ̌ɔ hìip', 'หอ หีบ', 'h', '—', _LetterClass.high),
  _Consonant('อ', 'ɔɔ àang', 'ออ อ่าง', '—', '—', _LetterClass.middle),
];

class _VowelExample {
  final String thai;
  final String reading;

  const _VowelExample(this.thai, this.reading);
}

// 位置ごとの母音。内側のリストが1段で、i 系と ʉ 系のように音の系統で段を分ける。
const _vowelPositions = <List<List<_VowelExample>>>[
  [
    [
      _VowelExample('เอ', 'ee'),
      _VowelExample('แอ', 'ɛɛ'),
      _VowelExample('โอ', 'oo')
    ],
  ],
  [
    [_VowelExample('อะ', 'a'), _VowelExample('อา', 'aa')],
  ],
  [
    [_VowelExample('อิ', 'i'), _VowelExample('อี', 'ii')],
    [_VowelExample('อึ', 'ʉ'), _VowelExample('อือ', 'ʉʉ')],
  ],
  [
    [_VowelExample('อุ', 'u'), _VowelExample('อู', 'uu')],
  ],
  [
    [_VowelExample('เอา', 'aw'), _VowelExample('เอีย', 'ia')],
  ],
];

const _vowelPairs = [
  [_VowelExample('อะ', 'a'), _VowelExample('อา', 'aa')],
  [_VowelExample('อิ', 'i'), _VowelExample('อี', 'ii')],
  [_VowelExample('อุ', 'u'), _VowelExample('อู', 'uu')],
  [_VowelExample('เอะ', 'e'), _VowelExample('เอ', 'ee')],
  [_VowelExample('แอะ', 'ɛ'), _VowelExample('แอ', 'ɛɛ')],
  [_VowelExample('โอะ', 'o'), _VowelExample('โอ', 'oo')],
  [_VowelExample('เอาะ', 'ɔ'), _VowelExample('ออ', 'ɔɔ')],
  [_VowelExample('เออะ', 'ə'), _VowelExample('เออ', 'əə')],
];

class _ToneMark {
  final String mark;
  final String name;
  final String spokenName;

  const _ToneMark(this.mark, this.name, this.spokenName);
}

const _toneMarks = [
  _ToneMark('่', 'mái èek', 'ไม้เอก'),
  _ToneMark('้', 'mái thoo', 'ไม้โท'),
  _ToneMark('๊', 'mái trii', 'ไม้ตรี'),
  _ToneMark('๋', 'mái jàttawaa', 'ไม้จัตวา'),
];

class _WordExample {
  final String thai;
  final String reading;
  final String initialConsonant;
  final String vowel;
  final String? finalConsonant;
  final String? toneMark;

  const _WordExample(
    this.thai,
    this.reading, {
    required this.initialConsonant,
    required this.vowel,
    this.finalConsonant,
    this.toneMark,
  });
}

const _words = [
  _WordExample('ไม่', 'mâi', initialConsonant: 'ม', vowel: 'ไ', toneMark: '่'),
  _WordExample('ดี', 'dii', initialConsonant: 'ด', vowel: 'ี'),
  _WordExample('เรา', 'raw', initialConsonant: 'ร', vowel: 'เ–า'),
  _WordExample('กิน', 'kin',
      initialConsonant: 'ก', vowel: 'ิ', finalConsonant: 'น'),
  _WordExample('มา', 'maa', initialConsonant: 'ม', vowel: 'า'),
];

/// よく出る文字から、タイ語の綴りを読む入口を作るガイド。
class ThaiScriptGuideScreen extends StatelessWidget {
  static const routeName = 'thai_script_guide';

  const ThaiScriptGuideScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.thaiScriptGuideTitle)),
      body: SwipeBack(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppConfig.defaultPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _IntroCard(
                heading: l10n.thaiScriptGuideHeading,
                body: l10n.thaiScriptGuideIntro,
              ),
              const SizedBox(height: 12),
              const _BasicsCard(),
              const SizedBox(height: 12),
              const _ConsonantsCard(),
              const SizedBox(height: 12),
              const _VowelsCard(),
              const SizedBox(height: 12),
              const _ToneMarksCard(),
              const SizedBox(height: 12),
              const _WordsCard(),
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
    final foreground = theme.colorScheme.onPrimaryContainer;
    return Card(
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(AppConfig.defaultPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.info_outline, color: foreground, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  heading,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: foreground,
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            Text(body,
                style: theme.textTheme.bodyMedium?.copyWith(color: foreground)),
          ],
        ),
      ),
    );
  }
}

class _GuideCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<Widget> children;

  const _GuideCard({
    required this.icon,
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppConfig.defaultPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, color: theme.colorScheme.primary, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _BasicsCard extends StatelessWidget {
  const _BasicsCard();

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    return _GuideCard(
      icon: Icons.account_tree_outlined,
      title: l10n.thaiScriptBasicsTitle,
      children: [
        Text(l10n.thaiScriptBasicsBody),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 6,
            runSpacing: 6,
            children: [
              _PartLegend(
                  text: 'ก',
                  label: l10n.thaiScriptConsonantLabel,
                  color: _consonantColor(theme)),
              const Text('+'),
              _PartLegend(
                  text: 'ิ',
                  label: l10n.thaiScriptVowelLabel,
                  color: _vowelColor(theme)),
              const Text('+'),
              _PartLegend(
                  text: 'น',
                  label: l10n.thaiScriptFinalConsonantLabel,
                  color: _consonantColor(theme)),
              const Text('→'),
              Text('กิน',
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _InfoLine(Icons.arrow_forward, l10n.thaiScriptBasicsDirection),
        const SizedBox(height: 8),
        _InfoLine(Icons.open_with, l10n.thaiScriptBasicsVowelPosition),
      ],
    );
  }
}

class _ConsonantsCard extends StatelessWidget {
  const _ConsonantsCard();

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return _GuideCard(
      icon: Icons.abc,
      title: l10n.thaiScriptConsonantsTitle,
      children: [
        Text(l10n.thaiScriptConsonantsBody),
        const SizedBox(height: 12),
        LayoutBuilder(builder: (context, constraints) {
          const gap = 8.0;
          final width = (constraints.maxWidth - gap) / 2;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final consonant in _consonants)
                SizedBox(
                  width: width,
                  child: _ConsonantTile(consonant: consonant),
                ),
            ],
          );
        }),
        const SizedBox(height: 10),
        _InfoLine(Icons.info_outline, l10n.thaiScriptConsonantCarrierNote),
      ],
    );
  }
}

class _ConsonantTile extends ConsumerWidget {
  final _Consonant consonant;

  const _ConsonantTile({required this.consonant});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    final className = switch (consonant.letterClass) {
      _LetterClass.middle => l10n.consonantClassMiddle,
      _LetterClass.high => l10n.consonantClassHigh,
      _LetterClass.low => l10n.consonantClassLow,
    };
    final classColor = switch (consonant.letterClass) {
      _LetterClass.middle => Colors.blue,
      _LetterClass.high => Colors.red,
      _LetterClass.low => Colors.green,
    };
    return _TappableTile(
      spokenText: consonant.spokenName,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Text(consonant.letter,
                    style: theme.textTheme.headlineMedium?.copyWith(
                        fontSize: 44,
                        height: 1.25,
                        fontWeight: FontWeight.w600)),
              ),
              Icon(Icons.volume_up_outlined,
                  size: 17, color: theme.colorScheme.primary),
            ]),
            Text(consonant.name,
                maxLines: 1,
                overflow: TextOverflow.fade,
                softWrap: false,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.primary)),
            const SizedBox(height: 4),
            Text(
              l10n.thaiScriptConsonantSounds(
                  consonant.initial, consonant.finalSound),
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: classColor.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(className, style: theme.textTheme.labelSmall),
            ),
          ],
        ),
      ),
    );
  }
}

class _VowelsCard extends StatelessWidget {
  const _VowelsCard();

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    final positionNames = l10n.thaiScriptVowelPositions.split('|');
    return _GuideCard(
      icon: Icons.text_format,
      title: l10n.thaiScriptVowelsTitle,
      children: [
        Text(l10n.thaiScriptVowelsBody),
        const SizedBox(height: 12),
        for (final (index, rows) in _vowelPositions.indexed) ...[
          if (index > 0) const Divider(height: 17),
          Text(
            index < positionNames.length ? positionNames[index] : '',
            style: theme.textTheme.labelLarge
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 6),
          for (final (rowIndex, vowels) in rows.indexed) ...[
            if (rowIndex > 0) const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [for (final vowel in vowels) _VowelTile(vowel: vowel)],
            ),
          ],
        ],
        const SizedBox(height: 16),
        Text(l10n.thaiScriptVowelPairsTitle,
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(l10n.thaiScriptVowelPairsBody,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 8),
        for (final pair in _vowelPairs) ...[
          Row(children: [
            Expanded(child: _VowelTile(vowel: pair[0], expanded: true)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              // 文字の ↔ は iOS で絵文字に化けるのでアイコンにする。
              child: Icon(Icons.swap_horiz,
                  size: 20, color: theme.colorScheme.outline),
            ),
            Expanded(child: _VowelTile(vowel: pair[1], expanded: true)),
          ]),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _VowelTile extends ConsumerWidget {
  final _VowelExample vowel;
  final bool expanded;

  const _VowelTile({required this.vowel, this.expanded = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return _TappableTile(
      spokenText: vowel.thai,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(vowel.thai,
                style: theme.textTheme.titleLarge?.copyWith(
                    fontSize: 34, height: 1.4, fontWeight: FontWeight.w600)),
            const SizedBox(width: 8),
            if (expanded)
              Expanded(
                child: Text(vowel.reading,
                    style: TextStyle(color: theme.colorScheme.primary)),
              )
            else
              Text(vowel.reading,
                  style: TextStyle(color: theme.colorScheme.primary)),
            const SizedBox(width: 6),
            Icon(Icons.volume_up_outlined,
                size: 16, color: theme.colorScheme.primary),
          ],
        ),
      ),
    );
  }
}

class _ToneMarksCard extends StatelessWidget {
  const _ToneMarksCard();

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    return _GuideCard(
      icon: Icons.graphic_eq,
      title: l10n.thaiScriptToneMarksTitle,
      children: [
        Text(l10n.thaiScriptToneMarksBody),
        const SizedBox(height: 12),
        LayoutBuilder(builder: (context, constraints) {
          const gap = 8.0;
          final width = (constraints.maxWidth - gap) / 2;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final tone in _toneMarks)
                SizedBox(width: width, child: _ToneMarkTile(tone: tone)),
            ],
          );
        }),
        const SizedBox(height: 12),
        _InfoLine(Icons.calculate_outlined, l10n.thaiScriptToneRule),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.graphic_eq),
            label: Text(l10n.thaiScriptOpenToneGuide),
            onPressed: () => Navigator.push(
              context,
              CupertinoPageRoute<void>(
                settings: const RouteSettings(name: ToneGuideScreen.routeName),
                builder: (_) => const ToneGuideScreen(),
              ),
            ),
          ),
        ),
        Text(l10n.thaiScriptToneGuideNote,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ],
    );
  }
}

class _ToneMarkTile extends ConsumerWidget {
  final _ToneMark tone;

  const _ToneMarkTile({required this.tone});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return _TappableTile(
      spokenText: tone.spokenName,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Column(children: [
          Text('อ${tone.mark}',
              style: theme.textTheme.headlineSmall?.copyWith(
                  fontSize: 40, height: 1.5, fontWeight: FontWeight.w600)),
          Text(tone.name,
              maxLines: 1,
              overflow: TextOverflow.fade,
              softWrap: false,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.primary)),
        ]),
      ),
    );
  }
}

class _WordsCard extends StatelessWidget {
  const _WordsCard();

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final meanings = l10n.thaiScriptWordMeanings.split('|');
    return _GuideCard(
      icon: Icons.extension_outlined,
      title: l10n.thaiScriptWordsTitle,
      children: [
        Text(l10n.thaiScriptWordsBody),
        const SizedBox(height: 12),
        _PartsKey(),
        const SizedBox(height: 10),
        for (final (index, word) in _words.indexed) ...[
          _WordTile(
            word: word,
            meaning: index < meanings.length ? meanings[index] : '',
          ),
          if (index < _words.length - 1) const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _PartsKey extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    return Wrap(spacing: 12, runSpacing: 5, children: [
      _DotLabel(_consonantColor(theme), l10n.thaiScriptConsonantLabel),
      _DotLabel(_vowelColor(theme), l10n.thaiScriptVowelLabel),
      _DotLabel(_toneColor(theme), l10n.thaiScriptToneMarkLabel),
    ]);
  }
}

class _WordTile extends ConsumerWidget {
  final _WordExample word;
  final String meaning;

  const _WordTile({required this.word, required this.meaning});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    return _TappableTile(
      spokenText: word.thai,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(word.thai,
                    style: theme.textTheme.headlineSmall?.copyWith(
                        fontSize: 40,
                        height: 1.4,
                        fontWeight: FontWeight.w600)),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(word.reading,
                          style: theme.textTheme.titleMedium
                              ?.copyWith(color: theme.colorScheme.primary)),
                      Text(meaning,
                          style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                Icon(Icons.volume_up_outlined,
                    size: 20, color: theme.colorScheme.primary),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              _PartChip(
                text: word.initialConsonant,
                label: l10n.thaiScriptConsonantLabel,
                color: _consonantColor(theme),
              ),
              _PartChip(
                text: word.vowel,
                label: l10n.thaiScriptVowelLabel,
                color: _vowelColor(theme),
              ),
              if (word.finalConsonant != null)
                _PartChip(
                  text: word.finalConsonant!,
                  label: l10n.thaiScriptFinalConsonantLabel,
                  color: _consonantColor(theme),
                ),
              if (word.toneMark != null)
                _PartChip(
                  text: word.toneMark!,
                  label: l10n.thaiScriptToneMarkLabel,
                  color: _toneColor(theme),
                ),
            ]),
          ],
        ),
      ),
    );
  }
}

class _TappableTile extends ConsumerWidget {
  final String spokenText;
  final Widget child;

  const _TappableTile({required this.spokenText, required this.child});

  void _speak(WidgetRef ref) {
    unawaited(ref.read(analyticsServiceProvider).logPlayTts(
          contentType: 'word',
          text: spokenText,
          source: 'thai_script_guide',
        ));
    unawaited(ref.read(ttsServiceProvider).speak(spokenText, keepVoice: true));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _speak(ref),
        child: Semantics(
          button: true,
          label: L10n.of(context).playPronunciation,
          child: child,
        ),
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  final IconData icon;
  final String text;

  const _InfoLine(this.icon, this.text);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, size: 18, color: theme.colorScheme.primary),
      const SizedBox(width: 8),
      Expanded(child: Text(text)),
    ]);
  }
}

class _PartLegend extends StatelessWidget {
  final String text;
  final String label;
  final Color color;

  const _PartLegend(
      {required this.text, required this.label, required this.color});

  @override
  Widget build(BuildContext context) => _PartChip(
        text: text,
        label: label,
        color: color,
      );
}

/// 子音の上下に付く記号（母音記号・声調記号）か。単独では台が要る。
bool _isCombiningMark(String text) {
  if (text.isEmpty) return false;
  final c = text.runes.first;
  return c == 0x0E31 ||
      (c >= 0x0E34 && c <= 0x0E3A) ||
      (c >= 0x0E47 && c <= 0x0E4E);
}

class _PartChip extends StatelessWidget {
  final String text;
  final String label;
  final Color color;

  const _PartChip(
      {required this.text, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final glyphStyle = theme.textTheme.titleMedium?.copyWith(
        fontSize: 30, height: 1.5, color: color, fontWeight: FontWeight.w600);
    return Container(
      constraints: const BoxConstraints(minWidth: 64),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (_isCombiningMark(text))
          // 上下に付く記号だけでは点にしか見えないので、อ を台にして子音の
          // どこに付くかを見せる。台と記号は1つの字形に組まれて色を分けられ
          // ないため、同じ位置に อ だけを地の色で重ねて台を薄くする。
          Stack(children: [
            Text('อ$text', style: glyphStyle),
            Text('อ',
                style: glyphStyle?.copyWith(
                    color: Color.alphaBlend(color.withValues(alpha: 0.13),
                            theme.colorScheme.surfaceContainerHigh)
                        .withValues(alpha: 0.7))),
          ])
        else
          Text(text, style: glyphStyle),
        Text(label, style: theme.textTheme.labelMedium?.copyWith(color: color)),
      ]),
    );
  }
}

class _DotLabel extends StatelessWidget {
  final Color color;
  final String label;

  const _DotLabel(this.color, this.label);

  @override
  Widget build(BuildContext context) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(label, style: Theme.of(context).textTheme.labelMedium),
      ]);
}

Color _consonantColor(ThemeData theme) => theme.colorScheme.primary;
Color _vowelColor(ThemeData theme) => Colors.teal.shade700;
Color _toneColor(ThemeData theme) => Colors.deepOrange.shade700;
