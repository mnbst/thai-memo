// =============================================================================
// tone_shift_table.dart
// 子音の階級ごとの声調変化表。声調ダイアログ・声調ガイド・綴りの分解で共用する。
// =============================================================================

import 'package:flutter/material.dart';

import '../../core/thai_tone_analyzer.dart';
import '../../l10n/app_localizations.dart';

/// [toneMark] と [syllableType] を渡すと、当てはまる行を強調する。
class ToneShiftTable extends StatelessWidget {
  final ConsonantClass consonantClass;
  final ToneMark? toneMark;
  final SyllableType? syllableType;
  final bool? hasShortVowel;

  const ToneShiftTable({
    super.key,
    required this.consonantClass,
    this.toneMark,
    this.syllableType,
    this.hasShortVowel,
  });

  /// 規則の表と違う声調で読む語（กราฟ、ก็ など）か。当てはまる行が無いときは
  /// 判断しない。母音の長短が不明だと行が複数当たるので、どれかが合えば例外にしない。
  static bool isException({
    required ConsonantClass consonantClass,
    required ToneMark toneMark,
    required SyllableType syllableType,
    required ThaiTone tone,
    bool? hasShortVowel,
  }) {
    if (tone == ThaiTone.unknown) return false;
    final hits = ThaiToneAnalyzer.getToneTable(consonantClass).where(
      (rule) =>
          rule.matches(toneMark, syllableType, hasShortVowel: hasShortVowel),
    );
    return hits.isNotEmpty && !hits.any((rule) => rule.resultingTone == tone);
  }

  bool _isHit(ToneRule rule) {
    final mark = toneMark;
    final type = syllableType;
    if (mark == null || type == null) return false;
    return rule.matches(mark, type, hasShortVowel: hasShortVowel);
  }

  @override
  Widget build(BuildContext context) {
    final rules = ThaiToneAnalyzer.getToneTable(consonantClass);
    if (rules.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    return Card(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Table(
          border: TableBorder.all(color: theme.dividerColor, width: 1),
          columnWidths: const {
            0: FlexColumnWidth(2),
            1: FlexColumnWidth(2),
            2: FlexColumnWidth(2),
          },
          children: [
            TableRow(
              decoration: BoxDecoration(
                color: theme.colorScheme.secondaryContainer,
              ),
              children: [
                _textCell(context, l10n.toneMarkLabel, isHeader: true),
                _textCell(context, l10n.toneSyllableType, isHeader: true),
                _textCell(context, l10n.toneResultTone, isHeader: true),
              ],
            ),
            for (final rule in rules) _dataRow(context, rule),
          ],
        ),
      ),
    );
  }

  TableRow _dataRow(BuildContext context, ToneRule rule) {
    final l10n = L10n.of(context);
    final hit = _isHit(rule);
    // 低子音の死音節だけは母音の長短で行が分かれる。
    final syllable =
        rule.syllableType == SyllableType.dead && rule.isShortVowel != null
            ? rule.syllableType
                .getDisplayNameWithVowel(l10n, hasShortVowel: rule.isShortVowel)
            : rule.syllableType.displayName(l10n);

    return TableRow(
      decoration: BoxDecoration(
        color: hit
            ? Theme.of(context).colorScheme.primaryContainer
            : Colors.transparent,
      ),
      children: [
        _toneMarkCell(context, rule.toneMark, hit),
        _textCell(context, syllable, hit: hit),
        _toneResultCell(context, rule.resultingTone, hit),
      ],
    );
  }

  Widget _textCell(
    BuildContext context,
    String text, {
    bool isHeader = false,
    bool hit = false,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: isHeader || hit ? FontWeight.bold : FontWeight.normal,
          fontSize: 14,
          color: hit
              ? theme.colorScheme.onPrimaryContainer
              : isHeader
                  ? theme.colorScheme.onSecondaryContainer
                  : theme.colorScheme.onSurface,
        ),
      ),
    );
  }

  Widget _toneMarkCell(BuildContext context, ToneMark mark, bool hit) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Text(
        mark.symbol(L10n.of(context)),
        textAlign: TextAlign.center,
        style: theme.textTheme.titleLarge?.copyWith(
          fontWeight: hit ? FontWeight.bold : FontWeight.normal,
          fontSize: mark == ToneMark.none ? 14 : 24,
          color: hit
              ? theme.colorScheme.onPrimaryContainer
              : theme.colorScheme.onSurface,
          height: 1.2,
        ),
      ),
    );
  }

  /// 声調名と、その下に上げ下げの記号。
  Widget _toneResultCell(BuildContext context, ThaiTone tone, bool hit) {
    final theme = Theme.of(context);
    final color = hit
        ? theme.colorScheme.onPrimaryContainer
        : theme.colorScheme.onSurface;
    final weight = hit ? FontWeight.bold : FontWeight.normal;
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            tone.displayName(L10n.of(context)),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: weight,
              fontSize: 14,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            tone.symbol,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: weight,
              fontSize: 20,
              color: color,
              fontFamily: 'monospace',
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}
