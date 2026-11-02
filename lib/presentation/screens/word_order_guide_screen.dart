import 'package:flutter/material.dart';

import '../../core/config/app_config.dart';
import '../../core/constants/word_order_rules.dart';
import '../../l10n/app_localizations.dart';
import '../widgets/swipe_back.dart';
import '../widgets/word_order_example.dart';

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
              for (final (i, rule) in wordOrderRules.indexed) ...[
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
  final WordOrderRule rule;

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
  'ที่': 'thîi',
  'กับ': 'kàp',
  'ใน': 'nai',
  'บน': 'bon',
  'ให้': 'hâi',
  'มาก': 'mâak',
  'จริงๆ': 'jing-jing',
  'นิดหน่อย': 'nít-nɔ̀i',
  'กว่า': 'kwàa',
  'ที่สุด': 'thîi-sùt',
  'อยาก': 'yàak',
  'ต้อง': 'tɔ̂ng',
  'ควร': 'khuan',
  'ได้': 'dâai',
  'ไป': 'pai',
  'ซื้อ': 'sʉ́ʉ',
  'มา': 'maa',
  'นะ': 'ná',
  'เลย': 'ləəi',
  'ด้วย': 'dûay',
  'ทำไม': 'tham-mai',
  'เป็น': 'pen',
  'หนึ่ง': 'nʉ̀ng',
  'นะคะ': 'ná khá',
  'อาบน้ำ': 'àap-náam',
  'นอน': 'nɔɔn',
  'เดิน': 'dəən',
  'กลับ': 'klàp',
  'บ้าน': 'bâan',
  'หมด': 'mòt',
  'เสร็จ': 'sèt',
  'ต่อ': 'tɔ̀ɔ',
  'ลองๆ': 'lɔɔng-lɔɔng',
  'ดู': 'duu',
  'เดินๆ': 'dəən-dəən',
  'หยุดๆ': 'yùt-yùt',
  'ดูๆ': 'duu-duu',
  'ก่อน': 'kɔ̀ɔn',
  'เร็วๆ': 'reo-reo',
  'บ่อยๆ': 'bɔ̀i-bɔ̀i',
  'เด็กๆ': 'dèk-dèk',
  'บ้านใหญ่': 'bâan yài',
  'แมวตัวหนึ่ง': 'mɛɛw tua nʉ̀ng',
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
