import 'package:flutter/material.dart';

import '../../core/config/app_config.dart';
import '../../core/thai_tone_analyzer.dart';

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
        title: const Text('タイ語の声調ガイド'),
      ),
      body: SingleChildScrollView(
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
                    'タイ語の声調について',
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
              'タイ語には5つの声調があり、同じ綴りでも声調によって意味が変わります。声調は、主子音（声調を決める子音）のクラス、声調記号、音節タイプによって決まります。',
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
        'description': '音の高さが平らで変化しない声調です。',
        'example': 'กา (gaa) カラス'
      },
      {
        'tone': ThaiTone.low,
        'description': '低い音から始まり、少し下がる声調です。',
        'example': 'ก่า (gàa) ガランガル'
      },
      {
        'tone': ThaiTone.falling,
        'description': '高い音から低く落ちる声調です。',
        'example': 'ก้า (gâa) 歩み'
      },
      {
        'tone': ThaiTone.high,
        'description': '高い音で始まり、さらに上がる声調です。',
        'example': 'ก๊า (gáa) 〜だよ（語尾）'
      },
      {
        'tone': ThaiTone.rising,
        'description': '低い音から高く上がる声調です。',
        'example': 'ก๋า (gǎa) 〜だね（語尾）'
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
                  '5つの声調',
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
                  tone.displayName,
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
                  '例: $example',
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
                  '子音クラス',
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
        consonantClass.displayName,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
      ),
      subtitle: Text(
        '${consonants.length}文字',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '例: ${consonantClass.exampleConsonants}',
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
        'description': '第1声調記号。子音クラスによって異なる声調になります。',
      },
      {
        'mark': ToneMark.maiTho,
        'thaiName': 'ไม้โท',
        'description': '第2声調記号。子音クラスによって異なる声調になります。',
      },
      {
        'mark': ToneMark.maiTri,
        'thaiName': 'ไม้ตรี',
        'description': '第3声調記号。中子音で使用。低子音・高子音では例外的です。',
      },
      {
        'mark': ToneMark.maiChattawa,
        'thaiName': 'ไม้จัตวา',
        'description': '第4声調記号。中子音で使用。低子音・高子音では例外的です。',
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
                  '声調記号',
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
                toneMark.symbol,
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
                      toneMark.displayName,
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
                  '音節タイプ',
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
                syllableType.displayName,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            syllableType.description,
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
                  '声調変化表',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              '子音クラスごとに、声調記号と音節タイプの組み合わせで決まる声調を示します。',
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
        '${consonantClass.displayName}の声調変化',
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
      ),
      subtitle: Text(
        '例: ${consonantClass.exampleConsonants}',
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
        _buildTableCell('声調記号', isHeader: true),
        _buildTableCell('音節タイプ', isHeader: true),
        _buildTableCell('結果の声調', isHeader: true),
      ],
    );
  }

  /// テーブルデータ行
  TableRow _buildTableDataRow(ToneRule rule) {
    // 音節タイプの表示（低子音の死音節は母音の長短を表示）
    String syllableTypeDisplay;
    if (rule.syllableType == SyllableType.dead && rule.isShortVowel != null) {
      syllableTypeDisplay = rule.syllableType
          .getDisplayNameWithVowel(hasShortVowel: rule.isShortVowel);
    } else {
      syllableTypeDisplay = rule.syllableType.displayName;
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
        toneMark.symbol,
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
            tone.displayName,
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
