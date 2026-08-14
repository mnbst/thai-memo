import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../core/config/app_config.dart';
import '../../core/thai_tone_analyzer.dart';
import '../widgets/swipe_back.dart';

/// タイ語の声調ガイド画面
class ToneGuideScreen extends StatefulWidget {
  static const routeName = 'tone_guide';

  const ToneGuideScreen({super.key});

  @override
  State<ToneGuideScreen> createState() => _ToneGuideScreenState();
}

class _ToneGuideScreenState extends State<ToneGuideScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(L10n.of(context).toneGuideTitle),
      ),
      body: SwipeBack(
        child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(AppConfig.defaultPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildIntroductionSection(),
              const SizedBox(height: 24),
              _buildFiveTonesSection(),
              const SizedBox(height: 24),
              _buildConsonantClassSection(),
              const SizedBox(height: 24),
              _buildToneMarksSection(),
              const SizedBox(height: 24),
              _buildSyllableTypesSection(),
              const SizedBox(height: 24),
              _buildToneTablesSection(),
              const SizedBox(height: 24),
            ],
          ),
          ),
        ),
      ),
    );
  }

  /// 導入セクション
  Widget _buildIntroductionSection() {
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(AppConfig.defaultPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.info_outline,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    L10n.of(context).toneGuideHeading,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color:
                              Theme.of(context).colorScheme.onPrimaryContainer,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              L10n.of(context).toneGuideIntro,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  /// 5つの声調セクション
  Widget _buildFiveTonesSection() {
    final tones = [
      {
        'tone': ThaiTone.mid,
        'description': L10n.of(context).toneMidDesc,
        'example': L10n.of(context).toneMidExample
      },
      {
        'tone': ThaiTone.low,
        'description': L10n.of(context).toneLowDesc,
        'example': L10n.of(context).toneLowExample
      },
      {
        'tone': ThaiTone.falling,
        'description': L10n.of(context).toneFallingDesc,
        'example': L10n.of(context).toneFallingExample
      },
      {
        'tone': ThaiTone.high,
        'description': L10n.of(context).toneHighDesc,
        'example': L10n.of(context).toneHighExample
      },
      {
        'tone': ThaiTone.rising,
        'description': L10n.of(context).toneRisingDesc,
        'example': L10n.of(context).toneRisingExample
      },
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppConfig.defaultPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.graphic_eq,
                  color: Theme.of(context).colorScheme.primary,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Text(
                  L10n.of(context).toneGuideFiveTones,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...tones.map((toneInfo) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _buildToneCard(
                    toneInfo['tone'] as ThaiTone,
                    toneInfo['description'] as String,
                    toneInfo['example'] as String,
                  ),
                )),
          ],
        ),
      ),
    );
  }

  /// 声調カード
  Widget _buildToneCard(ThaiTone tone, String description, String example) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          // 声調記号
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text(
                tone.symbol,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                      fontFamily: 'monospace',
                    ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // 説明
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tone.displayName(L10n.of(context)),
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 4),
                Text(
                  L10n.of(context).toneExamplePrefix(example),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.7),
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 子音クラスセクション
  Widget _buildConsonantClassSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppConfig.defaultPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.abc,
                  color: Theme.of(context).colorScheme.primary,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Text(
                  L10n.of(context).toneGuideConsonantClasses,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Builder(builder: (context) {
              final isDark = Theme.of(context).brightness == Brightness.dark;
              return Column(
                children: [
                  _buildConsonantClassExpansion(
                    ConsonantClass.high,
                    isDark ? Colors.red.shade900 : Colors.red.shade100,
                    ThaiToneAnalyzer.highConsonants,
                  ),
                  const SizedBox(height: 12),
                  _buildConsonantClassExpansion(
                    ConsonantClass.middle,
                    isDark ? Colors.blue.shade900 : Colors.blue.shade100,
                    ThaiToneAnalyzer.middleConsonants,
                  ),
                  const SizedBox(height: 12),
                  _buildConsonantClassExpansion(
                    ConsonantClass.low,
                    isDark ? Colors.green.shade900 : Colors.green.shade100,
                    ThaiToneAnalyzer.lowConsonants,
                  ),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }

  /// 子音クラスの展開パネル
  Widget _buildConsonantClassExpansion(
    ConsonantClass consonantClass,
    Color color,
    List<String> consonants,
  ) {
    return ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(horizontal: 8),
      backgroundColor: color.withValues(alpha: 0.3),
      collapsedBackgroundColor: color.withValues(alpha: 0.3),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      collapsedShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      title: Text(
        consonantClass.displayName(L10n.of(context)),
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
      ),
      subtitle: Text(
        L10n.of(context).toneGuideLetterCount(consonants.length),
        style: Theme.of(context).textTheme.bodySmall,
      ),
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                L10n.of(context)
                    .toneExamplePrefix(consonantClass.exampleConsonants),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.7),
                    ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: consonants.map((consonant) {
                  return Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Theme.of(context).dividerColor,
                        width: 1,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        consonant,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 声調記号セクション
  Widget _buildToneMarksSection() {
    final toneMarks = [
      {
        'mark': ToneMark.maiEk,
        'thaiName': 'ไม้เอก',
        'description': L10n.of(context).toneMarkMaiEkDesc,
      },
      {
        'mark': ToneMark.maiTho,
        'thaiName': 'ไม้โท',
        'description': L10n.of(context).toneMarkMaiThoDesc,
      },
      {
        'mark': ToneMark.maiTri,
        'thaiName': 'ไม้ตรี',
        'description': L10n.of(context).toneMarkMaiTriDesc,
      },
      {
        'mark': ToneMark.maiChattawa,
        'thaiName': 'ไม้จัตวา',
        'description': L10n.of(context).toneMarkMaiChattawaDesc,
      },
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppConfig.defaultPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.music_note,
                  color: Theme.of(context).colorScheme.primary,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Text(
                  L10n.of(context).toneGuideToneMarks,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...toneMarks.map((markInfo) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _buildToneMarkCard(
                    markInfo['mark'] as ToneMark,
                    markInfo['thaiName'] as String,
                    markInfo['description'] as String,
                  ),
                )),
          ],
        ),
      ),
    );
  }

  /// 声調記号カード
  Widget _buildToneMarkCard(
    ToneMark toneMark,
    String thaiName,
    String description,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          // 声調記号
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text(
                toneMark.symbol(L10n.of(context)),
                style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // 説明
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      toneMark.displayName(L10n.of(context)),
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      thaiName,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.7),
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 音節タイプセクション
  Widget _buildSyllableTypesSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppConfig.defaultPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.waves,
                  color: Theme.of(context).colorScheme.primary,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Text(
                  L10n.of(context).toneGuideSyllableTypes,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildSyllableTypeCard(
              SyllableType.live,
              Icons.radio_button_checked,
              Theme.of(context).brightness == Brightness.dark
                  ? Colors.green.shade300
                  : Colors.green,
            ),
            const SizedBox(height: 12),
            _buildSyllableTypeCard(
              SyllableType.dead,
              Icons.stop_circle,
              Theme.of(context).brightness == Brightness.dark
                  ? Colors.orange.shade300
                  : Colors.orange,
            ),
          ],
        ),
      ),
    );
  }

  /// 音節タイプカード
  Widget _buildSyllableTypeCard(
    SyllableType syllableType,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                color: color,
                size: 28,
              ),
              const SizedBox(width: 12),
              Text(
                syllableType.displayName(L10n.of(context)),
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            syllableType.description(L10n.of(context)),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }

  /// 声調変化表セクション
  Widget _buildToneTablesSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppConfig.defaultPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.table_chart,
                  color: Theme.of(context).colorScheme.primary,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Text(
                  L10n.of(context).toneGuideShiftTable,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              L10n.of(context).toneGuideShiftTableIntro,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.7),
                  ),
            ),
            const SizedBox(height: 16),
            _buildToneTableExpansion(ConsonantClass.middle),
            const SizedBox(height: 12),
            _buildToneTableExpansion(ConsonantClass.high),
            const SizedBox(height: 12),
            _buildToneTableExpansion(ConsonantClass.low),
          ],
        ),
      ),
    );
  }

  /// 声調変化表の展開パネル
  Widget _buildToneTableExpansion(ConsonantClass consonantClass) {
    final toneRules = ThaiToneAnalyzer.getToneTable(consonantClass);

    return ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(horizontal: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Theme.of(context).dividerColor),
      ),
      collapsedShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Theme.of(context).dividerColor),
      ),
      title: Text(
        L10n.of(context)
            .toneShiftFor(consonantClass.displayName(L10n.of(context))),
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
      ),
      subtitle: Text(
        L10n.of(context).toneExamplePrefix(consonantClass.exampleConsonants),
        style: Theme.of(context).textTheme.bodySmall,
      ),
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Table(
            border: TableBorder.all(
              color: Theme.of(context).dividerColor,
              width: 1,
            ),
            columnWidths: const {
              0: FlexColumnWidth(2),
              1: FlexColumnWidth(2),
              2: FlexColumnWidth(2),
            },
            children: [
              _buildTableHeaderRow(),
              ...toneRules.map((rule) => _buildTableDataRow(rule)),
            ],
          ),
        ),
      ],
    );
  }

  /// テーブルヘッダー行
  TableRow _buildTableHeaderRow() {
    return TableRow(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondaryContainer,
      ),
      children: [
        _buildTableCell(L10n.of(context).toneMarkLabel, isHeader: true),
        _buildTableCell(L10n.of(context).toneSyllableType, isHeader: true),
        _buildTableCell(L10n.of(context).toneResultTone, isHeader: true),
      ],
    );
  }

  /// テーブルデータ行
  TableRow _buildTableDataRow(ToneRule rule) {
    // 音節タイプの表示（低子音の死音節は母音の長短を表示）
    String syllableTypeDisplay;
    if (rule.syllableType == SyllableType.dead && rule.isShortVowel != null) {
      syllableTypeDisplay = rule.syllableType.getDisplayNameWithVowel(
          L10n.of(context),
          hasShortVowel: rule.isShortVowel);
    } else {
      syllableTypeDisplay = rule.syllableType.displayName(L10n.of(context));
    }

    return TableRow(
      children: [
        _buildToneMarkCell(rule.toneMark),
        _buildTableCell(syllableTypeDisplay),
        _buildToneResultCell(rule.resultingTone),
      ],
    );
  }

  /// テーブルセル
  Widget _buildTableCell(String text, {bool isHeader = false}) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: isHeader ? FontWeight.bold : FontWeight.normal,
              fontSize: 14,
              color: isHeader
                  ? Theme.of(context).colorScheme.onSecondaryContainer
                  : Theme.of(context).colorScheme.onSurface,
            ),
      ),
    );
  }

  /// 声調記号セル
  Widget _buildToneMarkCell(ToneMark toneMark) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Text(
        toneMark.symbol(L10n.of(context)),
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontSize: toneMark == ToneMark.none ? 14 : 24,
              color: Theme.of(context).colorScheme.onSurface,
              height: 1.2,
            ),
      ),
    );
  }

  /// 声調結果セル
  Widget _buildToneResultCell(ThaiTone tone) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            tone.displayName(L10n.of(context)),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontSize: 14,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            tone.symbol,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontSize: 20,
                  color: Theme.of(context).colorScheme.onSurface,
                  fontFamily: 'monospace',
                  height: 1.2,
                ),
          ),
        ],
      ),
    );
  }
}
