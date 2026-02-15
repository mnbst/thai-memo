import 'package:flutter/material.dart';

import '../../core/utils/thai_tone_analyzer.dart';
import '../../data/models/word_breakdown.dart';
import '../screens/tone_guide_screen.dart';

/// 声調解説を表示するダイアログ
class ToneExplanationDialog extends StatelessWidget {
  final String thaiWord;
  final ToneAnalysis analysis;
  final WordBreakdown? wordBreakdown;

  const ToneExplanationDialog({
    super.key,
    required this.thaiWord,
    required this.analysis,
    this.wordBreakdown,
  });

  @override
  Widget build(BuildContext context) {
    final syllables = wordBreakdown?.syllables;
    final hasSyllables = syllables != null && syllables.isNotEmpty;

    return Dialog(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 固定ヘッダー（スクロールしない）
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: _buildHeader(context),
          ),
          const SizedBox(height: 20),
          // スクロール可能なコンテンツ
          Flexible(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (hasSyllables) ...[
                      // 音節分解サマリー
                      _buildSyllableBreakdown(context),
                      const SizedBox(height: 20),
                      // 各音節の詳細分析
                      ...syllables.asMap().entries.map((entry) {
                        final index = entry.key;
                        final syllable = entry.value;
                        return Column(
                          children: [
                            _buildSyllableDetailCard(context, syllable, index + 1),
                            const SizedBox(height: 16),
                          ],
                        );
                      }),
                    ] else ...[
                      // 音節情報がない場合は単語全体の分析
                      _buildWordInfo(context),
                      const SizedBox(height: 20),
                      _buildToneTable(context),
                      const SizedBox(height: 20),
                    ],
                    _buildActionButtons(context),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// ヘッダー部分
  Widget _buildHeader(BuildContext context) {
    return Row(
      children: [
        Icon(
          Icons.graphic_eq,
          color: Theme.of(context).colorScheme.primary,
          size: 28,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            '声調の解説',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  /// 音節分解表示
  Widget _buildSyllableBreakdown(BuildContext context) {
    final syllables = wordBreakdown!.syllables!;
    final pronunciation = wordBreakdown!.pronunciation;

    return Card(
      color: Theme.of(context).colorScheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.layers,
                  size: 20,
                  color: Theme.of(context).colorScheme.onTertiaryContainer,
                ),
                const SizedBox(width: 8),
                Text(
                  '音節分解',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onTertiaryContainer,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: syllables.map((syllable) {
                return _buildSyllableChip(context, syllable);
              }).toList(),
            ),
            const SizedBox(height: 12),
            // ローマ字表記（拼音風）
            Text(
              pronunciation,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onTertiaryContainer,
                    letterSpacing: 0.5,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  /// 音節の詳細カード
  Widget _buildSyllableDetailCard(
    BuildContext context,
    syllable,
    int syllableNumber,
  ) {
    // SyllableデータからEnumに変換
    final consonantClass = ThaiToneAnalyzer.parseConsonantClass(syllable.consonantClass);
    final toneMark = ThaiToneAnalyzer.parseToneMark(syllable.toneMark);
    final syllableType = ThaiToneAnalyzer.parseSyllableType(syllable.syllableType);
    final resultingTone = ThaiToneAnalyzer.parseTone(syllable.tone);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 音節番号とテキスト
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '音節 $syllableNumber',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onPrimary,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  syllable.text,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 12),
            // 分析情報
            _buildInfoRow(
              context,
              '頭子音',
              '${syllable.initialConsonant} (${consonantClass.displayName})',
              Icons.abc,
            ),
            const SizedBox(height: 8),
            _buildToneMarkRow(context, toneMark),
            const SizedBox(height: 8),
            _buildInfoRow(
              context,
              '音節タイプ',
              syllableType.getDisplayNameWithVowel(hasShortVowel: syllable.hasShortVowel),
              Icons.waves,
            ),
            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 12),
            // 結果の声調
            Row(
              children: [
                Icon(
                  Icons.arrow_forward,
                  color: Theme.of(context).colorScheme.primary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  '結果: ',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                Text(
                  resultingTone.displayName,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                ),
                const SizedBox(width: 8),
                Text(
                  resultingTone.symbol,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                        fontFamily: 'monospace',
                      ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // 声調テーブル
            _buildCompactToneTable(context, consonantClass, toneMark, syllableType, syllable.hasShortVowel),
          ],
        ),
      ),
    );
  }

  /// コンパクト版の声調テーブル（音節ごとに表示用）
  Widget _buildCompactToneTable(
    BuildContext context,
    ConsonantClass consonantClass,
    ToneMark toneMark,
    SyllableType syllableType,
    bool? hasShortVowel,
  ) {
    final toneRules = ThaiToneAnalyzer.getToneTable(consonantClass);

    if (toneRules.isEmpty) {
      return const SizedBox.shrink();
    }

    // 高子音・低子音でmaiTri/maiChattawaの場合は注釈を表示
    final showExceptionalNote = (consonantClass == ConsonantClass.high ||
                                  consonantClass == ConsonantClass.low) &&
                                 (toneMark == ToneMark.maiTri ||
                                  toneMark == ToneMark.maiChattawa);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${consonantClass.displayName}の声調変化',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        if (showExceptionalNote) ...[
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.orange.shade100,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.orange.shade300),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.info_outline, size: 14, color: Colors.orange.shade900),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    '例外的な使用（現代では稀）',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.orange.shade900,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 8),
        Card(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Padding(
            padding: const EdgeInsets.all(8),
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
                // ヘッダー行
                _buildTableHeaderRow(context),
                // データ行
                ...toneRules.map((rule) => _buildTableDataRow(
                      context,
                      rule,
                      toneMark,
                      syllableType,
                      hasShortVowel,
                    )),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// 音節チップ
  Widget _buildSyllableChip(BuildContext context, syllable) {
    // 子音クラスに応じた色
    Color chipColor;
    switch (syllable.consonantClass.toLowerCase()) {
      case 'high':
        chipColor = Colors.red.shade100;
        break;
      case 'middle':
        chipColor = Colors.blue.shade100;
        break;
      case 'low':
        chipColor = Colors.green.shade100;
        break;
      default:
        chipColor = Colors.grey.shade100;
    }

    // 声調記号
    String toneSymbol;
    switch (syllable.tone.toLowerCase()) {
      case 'mid':
        toneSymbol = '—';
        break;
      case 'low':
        toneSymbol = '\\';
        break;
      case 'falling':
        toneSymbol = '^';
        break;
      case 'high':
        toneSymbol = '/';
        break;
      case 'rising':
        toneSymbol = 'v';
        break;
      default:
        toneSymbol = '?';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: chipColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Colors.grey.shade400,
          width: 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 音節テキスト
          Text(
            syllable.text,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  height: 1.2,
                ),
          ),
          const SizedBox(height: 4),
          // 子音と声調
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                syllable.initialConsonant,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(width: 4),
              Text(
                toneSymbol,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      fontFamily: 'monospace',
                    ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 単語情報
  Widget _buildWordInfo(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 単語
            Text(
              thaiWord,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
            ),
            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 12),
            // 分析結果
            _buildInfoRow(
              context,
              '頭子音',
              '${analysis.initialConsonant ?? "?"} (${analysis.consonantClass.displayName})',
              Icons.abc,
            ),
            const SizedBox(height: 8),
            _buildToneMarkRow(context, analysis.toneMark),
            const SizedBox(height: 8),
            _buildInfoRow(
              context,
              '音節タイプ',
              analysis.syllableType.getDisplayNameWithVowel(hasShortVowel: analysis.hasShortVowel),
              Icons.waves,
            ),
            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 12),
            // 結果
            Row(
              children: [
                Icon(
                  Icons.arrow_forward,
                  color: Theme.of(context).colorScheme.primary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  '結果: ',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                ),
                Text(
                  analysis.resultingTone.displayName,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                ),
                const SizedBox(width: 8),
                Text(
                  analysis.resultingTone.symbol,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                        fontFamily: 'monospace',
                      ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 情報行
  Widget _buildInfoRow(
    BuildContext context,
    String label,
    String value,
    IconData icon,
  ) {
    return Row(
      children: [
        Icon(
          icon,
          size: 16,
          color:
              Theme.of(context).colorScheme.onPrimaryContainer.withValues(alpha: 0.7),
        ),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context)
                    .colorScheme
                    .onPrimaryContainer
                    .withValues(alpha: 0.8),
              ),
        ),
        Expanded(
          child: Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
          ),
        ),
      ],
    );
  }

  /// 声調記号行（大きく表示）
  Widget _buildToneMarkRow(BuildContext context, ToneMark toneMark) {
    return Row(
      children: [
        Icon(
          Icons.music_note,
          size: 16,
          color:
              Theme.of(context).colorScheme.onPrimaryContainer.withValues(alpha: 0.7),
        ),
        const SizedBox(width: 8),
        Text(
          '声調記号: ',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context)
                    .colorScheme
                    .onPrimaryContainer
                    .withValues(alpha: 0.8),
              ),
        ),
        Expanded(
          child: Row(
            children: [
              Text(
                toneMark.displayName,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
              ),
              if (toneMark != ToneMark.none) ...[
                const SizedBox(width: 4),
                Text(
                  '(',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                ),
                Text(
                  toneMark.symbol,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                        height: 1.0,
                      ),
                ),
                Text(
                  ')',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// 声調テーブル
  Widget _buildToneTable(BuildContext context) {
    final toneRules = ThaiToneAnalyzer.getToneTable(analysis.consonantClass);

    if (toneRules.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.table_chart,
              size: 20,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Text(
              '${analysis.consonantClass.displayName}の声調変化表',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '例: ${analysis.consonantClass.exampleConsonants}',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.6),
              ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(8),
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
                // ヘッダー行
                _buildTableHeaderRow(context),
                // データ行
                ...toneRules.map((rule) => _buildTableDataRow(context, rule, null, null, null)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        _buildLegend(context),
      ],
    );
  }

  /// テーブルヘッダー行
  TableRow _buildTableHeaderRow(BuildContext context) {
    return TableRow(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondaryContainer,
      ),
      children: [
        _buildTableCell(
          context,
          '声調記号',
          isHeader: true,
        ),
        _buildTableCell(
          context,
          '音節タイプ',
          isHeader: true,
        ),
        _buildTableCell(
          context,
          '結果の声調',
          isHeader: true,
        ),
      ],
    );
  }

  /// テーブルデータ行
  TableRow _buildTableDataRow(
    BuildContext context,
    ToneRule rule,
    ToneMark? toneMarkOverride,
    SyllableType? syllableTypeOverride,
    bool? hasShortVowelOverride,
  ) {
    // 音節情報がある場合はそれを使用、ない場合は単語全体の分析を使用
    final toneMarkToUse = toneMarkOverride ?? analysis.toneMark;
    final syllableTypeToUse = syllableTypeOverride ?? analysis.syllableType;
    final hasShortVowelToUse = hasShortVowelOverride ?? analysis.hasShortVowel;

    final isHighlighted = rule.matches(
      toneMarkToUse,
      syllableTypeToUse,
      hasShortVowel: hasShortVowelToUse,
    );

    final backgroundColor = isHighlighted
        ? Theme.of(context).colorScheme.primaryContainer
        : Colors.transparent;

    // 低子音の死音節の場合は母音の長短を表示
    String syllableTypeDisplay;
    if (rule.syllableType == SyllableType.dead && rule.isShortVowel != null) {
      syllableTypeDisplay = rule.syllableType.getDisplayNameWithVowel(hasShortVowel: rule.isShortVowel);
    } else {
      syllableTypeDisplay = rule.syllableType.displayName;
    }

    return TableRow(
      decoration: BoxDecoration(color: backgroundColor),
      children: [
        _buildToneMarkCell(
          context,
          rule.toneMark,
          isHighlighted: isHighlighted,
        ),
        _buildTableCell(
          context,
          syllableTypeDisplay,
          isHighlighted: isHighlighted,
        ),
        _buildToneResultCell(
          context,
          rule.resultingTone,
          isHighlighted: isHighlighted,
        ),
      ],
    );
  }

  /// テーブルセル
  Widget _buildTableCell(
    BuildContext context,
    String text, {
    bool isHeader = false,
    bool isHighlighted = false,
    bool isToneResult = false,
  }) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: isHeader || isHighlighted ? FontWeight.bold : FontWeight.normal,
              fontSize: isToneResult ? 16 : 14,
              color: isHighlighted
                  ? Theme.of(context).colorScheme.onPrimaryContainer
                  : isHeader
                      ? Theme.of(context).colorScheme.onSecondaryContainer
                      : Theme.of(context).colorScheme.onSurface,
            ),
      ),
    );
  }

  /// 声調記号セル（大きく表示）
  Widget _buildToneMarkCell(
    BuildContext context,
    ToneMark toneMark, {
    bool isHighlighted = false,
  }) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Text(
        toneMark.symbol,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: isHighlighted ? FontWeight.bold : FontWeight.normal,
              fontSize: toneMark == ToneMark.none ? 14 : 24,
              color: isHighlighted
                  ? Theme.of(context).colorScheme.onPrimaryContainer
                  : Theme.of(context).colorScheme.onSurface,
              height: 1.2,
            ),
      ),
    );
  }

  /// 声調結果セル（声調名と記号を縦に表示）
  Widget _buildToneResultCell(
    BuildContext context,
    ThaiTone tone, {
    bool isHighlighted = false,
  }) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            tone.displayName,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: isHighlighted ? FontWeight.bold : FontWeight.normal,
                  fontSize: 14,
                  color: isHighlighted
                      ? Theme.of(context).colorScheme.onPrimaryContainer
                      : Theme.of(context).colorScheme.onSurface,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            tone.symbol,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: isHighlighted ? FontWeight.bold : FontWeight.normal,
                  fontSize: 20,
                  color: isHighlighted
                      ? Theme.of(context).colorScheme.onPrimaryContainer
                      : Theme.of(context).colorScheme.onSurface,
                  fontFamily: 'monospace',
                  height: 1.2,
                ),
          ),
        ],
      ),
    );
  }

  /// 凡例
  Widget _buildLegend(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            border: Border.all(
              color: Theme.of(context).dividerColor,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '= この単語に適用されている規則',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.6),
              ),
        ),
      ],
    );
  }

  /// アクションボタン
  Widget _buildActionButtons(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton.icon(
          onPressed: () {
            Navigator.of(context).pop();
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const ToneGuideScreen(),
              ),
            );
          },
          icon: const Icon(Icons.school),
          label: const Text('声調について詳しく学ぶ'),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('閉じる'),
        ),
      ],
    );
  }

  /// ダイアログを表示
  static void show(BuildContext context, String thaiWord, {WordBreakdown? wordBreakdown}) {
    final analysis = ThaiToneAnalyzer.analyzeTone(thaiWord);

    showDialog(
      context: context,
      builder: (context) => ToneExplanationDialog(
        thaiWord: thaiWord,
        analysis: analysis,
        wordBreakdown: wordBreakdown,
      ),
    );
  }
}
