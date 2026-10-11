import 'package:flutter/material.dart';

import '../../core/config/app_config.dart';
import '../../l10n/app_localizations.dart';
import '../widgets/swipe_back.dart';
import '../widgets/word_order_example.dart';

class _Rule {
  final String Function(L10n) title;
  final String Function(L10n) body;
  final List<WordOrderExample> examples;
  final String Function(L10n)? note;

  const _Rule(this.title, this.body, this.examples, [this.note]);
}

final _rules = <_Rule>[
  _Rule(
    (l) => l.wordOrderRule1Title,
    (l) => l.wordOrderRule1Body,
    [
      WordOrderExample(
          ['ทัวร์', 'นี้', 'คน', 'เยอะ'],
          ['thua', 'níi', 'khon', 'yə́'],
          {0, 1},
          (l) => l.wordOrderEx1aGloss,
          (l) => l.wordOrderEx1aMeaning),
      WordOrderExample(
          ['สนามบิน', 'คน', 'เยอะ'],
          ['sà-nǎam-bin', 'khon', 'yə́'],
          {0},
          (l) => l.wordOrderEx1bGloss,
          (l) => l.wordOrderEx1bMeaning),
    ],
    (l) => l.wordOrderRule1Note,
  ),
  _Rule(
    (l) => l.wordOrderRule2Title,
    (l) => l.wordOrderRule2Body,
    [
      WordOrderExample(
          ['รายงาน', 'นี้', 'พรุ่งนี้', 'ใช้', 'ได้', 'ไหม'],
          ['raai-ngaan', 'níi', 'phrûng-níi', 'chái', 'dâai', 'mǎi'],
          {0, 1},
          (l) => l.wordOrderEx2aGloss,
          (l) => l.wordOrderEx2aMeaning),
    ],
  ),
  _Rule(
    (l) => l.wordOrderRule3Title,
    (l) => l.wordOrderRule3Body,
    [
      WordOrderExample(['ผม', 'กิน', 'ข้าว'], ['phǒm', 'kin', 'khâaw'], {1},
          (l) => l.wordOrderEx3aGloss, (l) => l.wordOrderEx3aMeaning),
    ],
    (l) => l.wordOrderRule3Note,
  ),
  _Rule(
    (l) => l.wordOrderRule4Title,
    (l) => l.wordOrderRule4Body,
    [
      WordOrderExample(['บ้าน', 'ใหญ่'], ['bâan', 'yài'], {1},
          (l) => l.wordOrderEx4aGloss, (l) => l.wordOrderEx4aMeaning),
      WordOrderExample(['บ้าน', 'ของ', 'ผม'], ['bâan', 'khɔ̌ɔng', 'phǒm'],
          {1, 2}, (l) => l.wordOrderEx4bGloss, (l) => l.wordOrderEx4bMeaning),
    ],
    (l) => l.wordOrderRule4Note,
  ),
  _Rule(
    (l) => l.wordOrderRule5Title,
    (l) => l.wordOrderRule5Body,
    [
      WordOrderExample(['แมว', 'สอง', 'ตัว'], ['mɛɛw', 'sɔ̌ɔng', 'tua'], {1, 2},
          (l) => l.wordOrderEx5aGloss, (l) => l.wordOrderEx5aMeaning),
      WordOrderExample(
          ['แมว', 'สอง', 'ตัว', 'นี้'],
          ['mɛɛw', 'sɔ̌ɔng', 'tua', 'níi'],
          {1, 2, 3},
          (l) => l.wordOrderEx5bGloss,
          (l) => l.wordOrderEx5bMeaning),
    ],
  ),
  _Rule(
    (l) => l.wordOrderRule6Title,
    (l) => l.wordOrderRule6Body,
    [
      WordOrderExample(
          ['ผม', 'ไม่', 'กิน', 'เผ็ด'],
          ['phǒm', 'mâi', 'kin', 'phèt'],
          {1},
          (l) => l.wordOrderEx6aGloss,
          (l) => l.wordOrderEx6aMeaning),
      WordOrderExample(['ผม', 'ไม่ได้', 'ไป'], ['phǒm', 'mâi dâai', 'pai'], {1},
          (l) => l.wordOrderEx6bGloss, (l) => l.wordOrderEx6bMeaning),
      WordOrderExample(['ไป', 'ไม่ได้'], ['pai', 'mâi dâai'], {1},
          (l) => l.wordOrderEx6cGloss, (l) => l.wordOrderEx6cMeaning),
    ],
    (l) => l.wordOrderRule6Note,
  ),
  _Rule(
    (l) => l.wordOrderRule7Title,
    (l) => l.wordOrderRule7Body,
    [
      WordOrderExample(['คุณ', 'กิน', 'อะไร'], ['khun', 'kin', 'à-rai'], {2},
          (l) => l.wordOrderEx7aGloss, (l) => l.wordOrderEx7aMeaning),
      WordOrderExample(['ไป', 'ไหน'], ['pai', 'nǎi'], {1},
          (l) => l.wordOrderEx7bGloss, (l) => l.wordOrderEx7bMeaning),
      WordOrderExample(['กิน', 'ไหม'], ['kin', 'mǎi'], {1},
          (l) => l.wordOrderEx7cGloss, (l) => l.wordOrderEx7cMeaning),
    ],
  ),
  _Rule(
    (l) => l.wordOrderRule8Title,
    (l) => l.wordOrderRule8Body,
    [
      WordOrderExample(['ผม', 'จะ', 'ไป'], ['phǒm', 'jà', 'pai'], {1},
          (l) => l.wordOrderEx8aGloss, (l) => l.wordOrderEx8aMeaning),
      WordOrderExample(['กิน', 'ข้าว', 'แล้ว'], ['kin', 'khâaw', 'lɛ́ɛw'], {2},
          (l) => l.wordOrderEx8bGloss, (l) => l.wordOrderEx8bMeaning),
    ],
  ),
  _Rule(
    (l) => l.wordOrderRule9Title,
    (l) => l.wordOrderRule9Body,
    [
      WordOrderExample(
          ['พรุ่งนี้', 'ผม', 'จะ', 'ไป', 'เชียงใหม่'],
          ['phrûng-níi', 'phǒm', 'jà', 'pai', 'chiang-mài'],
          {0, 4},
          (l) => l.wordOrderEx9aGloss,
          (l) => l.wordOrderEx9aMeaning),
      WordOrderExample(
          ['ผม', 'ทำงาน', 'ที่', 'กรุงเทพฯ'],
          ['phǒm', 'tham-ngaan', 'thîi', 'krung-thêep'],
          {2, 3},
          (l) => l.wordOrderEx9bGloss,
          (l) => l.wordOrderEx9bMeaning),
    ],
  ),
  _Rule(
    (l) => l.wordOrderRule10Title,
    (l) => l.wordOrderRule10Body,
    [
      WordOrderExample(['กิน', 'ไหม', 'คะ'], ['kin', 'mǎi', 'khá'], {2},
          (l) => l.wordOrderEx10aGloss, (l) => l.wordOrderEx10aMeaning),
      WordOrderExample(['กิน', 'แล้ว', 'ค่ะ'], ['kin', 'lɛ́ɛw', 'khâ'], {2},
          (l) => l.wordOrderEx10bGloss, (l) => l.wordOrderEx10bMeaning),
    ],
  ),
];

/// タイ語の語順ガイド画面。並び替え問題の補助として、設定と解答画面から開く。
class WordOrderGuideScreen extends StatelessWidget {
  static const routeName = 'word_order_guide';

  const WordOrderGuideScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
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
              for (final (i, rule) in _rules.indexed) ...[
                _RuleCard(number: i + 1, rule: rule),
                const SizedBox(height: 12),
              ],
              const SizedBox(height: 12),
              _TipsCard(
                title: l10n.wordOrderTipsTitle,
                tips: l10n.wordOrderTipsBody.split('\n'),
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
  final int number;
  final _Rule rule;

  const _RuleCard({required this.number, required this.rule});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    final note = rule.note?.call(l10n);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppConfig.defaultPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 13,
                  backgroundColor: theme.colorScheme.primary,
                  child: Text(
                    '$number',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onPrimary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ReadingText(
                    rule.title(l10n),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _ReadingText(rule.body(l10n), style: theme.textTheme.bodyMedium),
            for (final example in rule.examples) ...[
              const SizedBox(height: 12),
              WordOrderExampleView(example: example),
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
                    child: _ReadingText(
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

class _TipsCard extends StatelessWidget {
  final String title;
  final List<String> tips;

  const _TipsCard({required this.title, required this.tips});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppConfig.defaultPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.lightbulb_outline,
                    color: theme.colorScheme.primary, size: 24),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            for (final (i, tip) in tips.indexed) ...[
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${i + 1}.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _ReadingText(tip, style: theme.textTheme.bodyMedium),
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

/// 説明文に出てくるタイ語の読み。例文のチップと同じ表記にそろえる。
const _readings = {
  'นี้': 'níi',
  'นั้น': 'nán',
  'ไม่': 'mâi',
  'ไม่ได้': 'mâi dâai',
  'ไหม': 'mǎi',
  'จะ': 'jà',
  'กำลัง': 'kam-lang',
  'เคย': 'khəəi',
  'แล้ว': 'lɛ́ɛw',
  'ครับ': 'khráp',
  'ค่ะ': 'khâ',
  'คะ': 'khá',
  'ของ': 'khɔ̌ɔng',
};

final _thaiRun = RegExp(r'[฀-๿]+');

/// 説明文中のタイ語の直後に、読みを添えて表示する。
class _ReadingText extends StatelessWidget {
  final String text;
  final TextStyle? style;

  const _ReadingText(this.text, {this.style});

  @override
  Widget build(BuildContext context) {
    // 大きさは本文と同じにし、色で読みだと分かるようにする。
    final readingStyle = style?.copyWith(
      fontWeight: FontWeight.normal,
      color: Theme.of(context).colorScheme.primary,
    );
    final spans = <InlineSpan>[];
    var last = 0;
    for (final match in _thaiRun.allMatches(text)) {
      final thai = match.group(0)!;
      spans.add(TextSpan(text: text.substring(last, match.end)));
      final reading = _readings[thai];
      if (reading != null) {
        spans.add(TextSpan(text: ' $reading', style: readingStyle));
      }
      last = match.end;
    }
    spans.add(TextSpan(text: text.substring(last)));
    return Text.rich(TextSpan(style: style, children: spans));
  }
}
