import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../core/spelling_breakdown.dart';
import '../core/thai_tone_analyzer.dart';
import '../data/models/syllable.dart';
import '../data/models/word_breakdown.dart';
import 'screens/thai_script_guide_screen.dart';
import 'screens/tone_guide_screen.dart';
import 'widgets/spelling_breakdown_view.dart';
import 'widgets/tone_shift_table.dart';

/// 声調解説を表示するダイアログ
class ToneExplanationDialog extends StatelessWidget {
  final String thaiWord;
  final ToneAnalysis analysis;
  final WordBreakdown? wordBreakdown;

  /// 音節ごとの分解（wordBreakdown.syllables と同じ並び）。表に無い音節は null。
  /// 同じ綴りでも前の字で階級が変わるので、綴りでなく位置で対応させる。
  final List<SpellingBreakdown?> spelling;

  /// 初回ガイド用のスポット対象。ガイド中でなければ null（キーを付けない）。
  ///
  /// 表のキーは1つ目の音節カードにだけ付ける。同じ説明を音節の数だけ
  /// 繰り返しても読まれない。

  const ToneExplanationDialog({
    super.key,
    required this.thaiWord,
    required this.analysis,
    this.wordBreakdown,
    this.spelling = const [],
  });

  @override
  Widget build(BuildContext context) {
    final syllables = wordBreakdown?.syllables;
    final hasSyllables = syllables != null && syllables.isNotEmpty;

    return Dialog(
      // 綴りの分解や声調表に幅が要るので、標準の余白（左右40）より詰める。
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
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
                      KeyedSubtree(
                        child: _buildSyllableBreakdown(context),
                      ),
                      const SizedBox(height: 20),
                      // 各音節の詳細分析
                      ...syllables.asMap().entries.map((entry) {
                        final index = entry.key;
                        final syllable = entry.value;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (index > 0)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 16),
                                child: Divider(height: 1),
                              ),
                            _buildSyllableDetail(context, syllable, index + 1),
                          ],
                        );
                      }),
                      const SizedBox(height: 20),
                    ] else ...[
                      // 音節情報がない場合は単語全体の分析
                      KeyedSubtree(
                        child: _buildWordInfo(context),
                      ),
                      const SizedBox(height: 20),
                      KeyedSubtree(
                        child: _buildToneTable(context),
                      ),
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
            L10n.of(context).toneDialogTitle,
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
                  L10n.of(context).toneSyllableBreakdown,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color:
                            Theme.of(context).colorScheme.onTertiaryContainer,
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
                    fontSize: 20,
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

  /// 音節の詳細。カードで囲むと中の分解や表の幅が削られるので、線で区切るだけにする。
  Widget _buildSyllableDetail(
    BuildContext context,
    syllable,
    int syllableNumber,
  ) {
    // SyllableデータからEnumに変換
    final consonantClass =
        ThaiToneAnalyzer.parseConsonantClass(syllable.consonantClass);
    final toneMark = ThaiToneAnalyzer.parseToneMark(syllable.toneMark);
    final syllableType =
        ThaiToneAnalyzer.parseSyllableType(syllable.syllableType);
    final resultingTone = ThaiToneAnalyzer.parseTone(syllable.tone);
    final breakdown =
        syllableNumber <= spelling.length ? spelling[syllableNumber - 1] : null;
    final spellingRule = breakdown?.toneRule;
    final isToneException = ToneShiftTable.isException(
      consonantClass: consonantClass,
      toneMark: toneMark,
      syllableType: syllableType,
      tone: resultingTone,
      hasShortVowel: syllable.hasShortVowel,
    );
    return Column(
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
                L10n.of(context).toneSyllableNumber(syllableNumber),
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
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ],
        ),
        ..._buildSpelling(context, breakdown),
        // 分解できる音節は、綴り4択の答え合わせと同じ形にする。
        if (spellingRule != null) ...[
          // 階級を前の字から借りる音節は、規則の階級と字が合わなく見える。
          if (breakdown?.toneLeader != null) ...[
            const SizedBox(height: 12),
            _buildInfoRow(
              context,
              L10n.of(context).toneMainConsonant,
              '${syllable.initialConsonant} (${consonantClass.displayName(L10n.of(context))})',
              Icons.abc,
            ),
          ],
          const SizedBox(height: 12),
          SpellingToneRuleTile(
            parts: breakdown!.parts,
            rule: spellingRule,
          ),
        ] else ...[
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 12),
          // 声調記号と音節タイプは下の表の強調行と重なるので出さない。
          _buildInfoRow(
            context,
            L10n.of(context).toneMainConsonant,
            '${syllable.initialConsonant} (${consonantClass.displayName(L10n.of(context))})',
            Icons.abc,
          ),
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
                L10n.of(context).toneResultPrefix,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              Text(
                resultingTone.displayName(L10n.of(context)),
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                    ),
              ),
              if (isToneException)
                Text(
                  L10n.of(context).toneRuleException,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
          ),
          const SizedBox(height: 4),
          // どのような声調かの簡潔な説明
          Padding(
            padding: const EdgeInsets.only(left: 28),
            child: Text(
              resultingTone.description(L10n.of(context)),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
          const SizedBox(height: 16),
          // 声調テーブル
          KeyedSubtree(
            child: _buildCompactToneTable(context, consonantClass, toneMark,
                syllableType, syllable.hasShortVowel,
                highlight: !isToneException),
          ),
        ],
      ],
    );
  }

  /// 綴りの分解。表に無い綴りでは何も出さない。
  List<Widget> _buildSpelling(
    BuildContext context,
    SpellingBreakdown? breakdown,
  ) {
    if (breakdown == null) return const [];
    return [
      const SizedBox(height: 14),
      Row(
        children: [
          Icon(
            Icons.account_tree_outlined,
            size: 18,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Text(
            L10n.of(context).quizSpellingBreakdown,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontSize: 16,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      SpellingPartsRow(
        parts: breakdown.parts,
        glyphs: breakdown.glyphs,
        toneRule: breakdown.toneRule,
        glyphSize: 36,
      ),
    ];
  }

  /// コンパクト版の声調テーブル（音節ごとに表示用）
  Widget _buildCompactToneTable(
    BuildContext context,
    ConsonantClass consonantClass,
    ToneMark toneMark,
    SyllableType syllableType,
    bool? hasShortVowel, {
    required bool highlight,
  }) {
    final toneRules = ThaiToneAnalyzer.getToneTable(consonantClass);

    if (toneRules.isEmpty) {
      return const SizedBox.shrink();
    }

    // 高子音・低子音でmaiTri/maiChattawaの場合は注釈を表示
    final showExceptionalNote = (consonantClass == ConsonantClass.high ||
            consonantClass == ConsonantClass.low) &&
        (toneMark == ToneMark.maiTri || toneMark == ToneMark.maiChattawa);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          L10n.of(context)
              .toneShiftFor(consonantClass.displayName(L10n.of(context))),
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        if (showExceptionalNote) ...[
          const SizedBox(height: 4),
          Builder(builder: (context) {
            final isDarkMode = Theme.of(context).brightness == Brightness.dark;
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: isDarkMode
                    ? Colors.orange.shade900.withValues(alpha: 0.3)
                    : Colors.orange.shade100,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                    color: isDarkMode
                        ? Colors.orange.shade700
                        : Colors.orange.shade300),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.info_outline,
                      size: 14,
                      color: isDarkMode
                          ? Colors.orange.shade300
                          : Colors.orange.shade900),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      L10n.of(context).toneRareUsage,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: isDarkMode
                                ? Colors.orange.shade300
                                : Colors.orange.shade900,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
        const SizedBox(height: 8),
        ToneShiftTable(
          consonantClass: consonantClass,
          toneMark: highlight ? toneMark : null,
          syllableType: syllableType,
          hasShortVowel: hasShortVowel,
        ),
      ],
    );
  }

  /// 音節チップ
  Widget _buildSyllableChip(BuildContext context, syllable) {
    final consonantClass =
        ThaiToneAnalyzer.parseConsonantClass(syllable.consonantClass);
    // 子音クラスに応じた色（ダークモード対応）
    final isDark = Theme.of(context).brightness == Brightness.dark;
    Color chipColor;
    switch (syllable.consonantClass.toLowerCase()) {
      case 'high':
        chipColor = isDark ? Colors.red.shade900 : Colors.red.shade100;
        break;
      case 'middle':
        chipColor = isDark ? Colors.blue.shade900 : Colors.blue.shade100;
        break;
      case 'low':
        chipColor = isDark ? Colors.green.shade900 : Colors.green.shade100;
        break;
      default:
        chipColor = isDark ? Colors.grey.shade800 : Colors.grey.shade100;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: chipColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Theme.of(context).dividerColor,
          width: 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            syllable.text,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                  height: 1.2,
                ),
          ),
          // 色だけで階級を区別させない。
          if (consonantClass != ConsonantClass.unknown)
            Text(
              consonantClass.displayName(L10n.of(context)),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontSize: 13,
                  ),
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
              L10n.of(context).toneMainConsonant,
              '${analysis.initialConsonant ?? "?"} (${analysis.consonantClass.displayName(L10n.of(context))})',
              Icons.abc,
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
                  L10n.of(context).toneResultPrefix,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                ),
                Text(
                  analysis.resultingTone.displayName(L10n.of(context)),
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            // どのような声調かの簡潔な説明
            Padding(
              padding: const EdgeInsets.only(left: 28),
              child: Text(
                analysis.resultingTone.description(L10n.of(context)),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onPrimaryContainer
                          .withValues(alpha: 0.7),
                    ),
              ),
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
          color: Theme.of(context)
              .colorScheme
              .onPrimaryContainer
              .withValues(alpha: 0.7),
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
              L10n.of(context).toneShiftTableFor(
                  analysis.consonantClass.displayName(L10n.of(context))),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          L10n.of(context)
              .toneExamplePrefix(analysis.consonantClass.exampleConsonants),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.6),
              ),
        ),
        const SizedBox(height: 12),
        ToneShiftTable(
          consonantClass: analysis.consonantClass,
          toneMark: analysis.toneMark,
          syllableType: analysis.syllableType,
          hasShortVowel: analysis.hasShortVowel,
        ),
        const SizedBox(height: 8),
        _buildLegend(context),
      ],
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
          L10n.of(context).toneAppliedRule,
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
  /// 規則の欄（中に声調ガイドへのボタンがある）を出せない音節があるか。
  bool get _needsToneGuideButton {
    final count = wordBreakdown?.syllables?.length ?? 0;
    if (count == 0) return true;
    for (var i = 0; i < count; i++) {
      if (i >= spelling.length || spelling[i]?.toneRule == null) return true;
    }
    return false;
  }

  Widget _buildActionButtons(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_needsToneGuideButton) ...[
          OutlinedButton.icon(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.push(
                context,
                CupertinoPageRoute(
                  settings:
                      const RouteSettings(name: ToneGuideScreen.routeName),
                  builder: (context) => const ToneGuideScreen(),
                ),
              );
            },
            icon: const Icon(Icons.graphic_eq),
            label: Text(L10n.of(context).toneLearnMore),
          ),
          const SizedBox(height: 12),
        ],
        OutlinedButton.icon(
          onPressed: () {
            Navigator.of(context).pop();
            Navigator.push(
              context,
              CupertinoPageRoute(
                settings:
                    const RouteSettings(name: ThaiScriptGuideScreen.routeName),
                builder: (context) => const ThaiScriptGuideScreen(),
              ),
            );
          },
          icon: const Icon(Icons.school),
          label: Text(L10n.of(context).thaiScriptLearnMore),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(L10n.of(context).commonClose),
        ),
      ],
    );
  }

  /// 分解できる音節は、声調の表示も分解に合わせる。2音で読む単位（ตลาด）は
  /// 分解と同じ単位に割る。音節の情報が無い語は語全体を1単位として扱う。
  static (WordBreakdown, List<SpellingBreakdown?>) _alignedWithSpelling(
    WordBreakdown word,
    String thaiWord,
    SpellingIndex index,
  ) {
    final syllables = word.syllables;
    final source = syllables == null || syllables.isEmpty
        ? [Syllable.fromText(thaiWord)]
        : syllables;
    final spelling = <SpellingBreakdown?>[];
    final aligned = <Syllable>[];
    for (final syllable in source) {
      final items = index.items(syllable.text);
      if (items.isEmpty) {
        aligned.add(syllable);
        spelling.add(null);
        continue;
      }
      for (final item in items) {
        final base = item.text == syllable.text
            ? syllable
            : Syllable.fromText(item.text);
        aligned.add(item.breakdown.applyTo(base));
        spelling.add(item.breakdown);
      }
    }
    final hasNone = spelling.every((b) => b == null) &&
        (syllables == null || syllables.isEmpty);
    return (hasNone ? word : word.copyWith(syllables: aligned), spelling);
  }

  /// ダイアログを表示する。閉じられるまで待てる。
  static Future<void> show(
    BuildContext context,
    String thaiWord, {
    WordBreakdown? wordBreakdown,
  }) async {
    final analysis = ThaiToneAnalyzer.analyzeTone(thaiWord);
    SpellingIndex? spellingIndex;
    try {
      spellingIndex = await SpellingIndex.load();
    } catch (_) {
      // 分解が出ないだけで、声調の解説は開ける。
    }
    if (!context.mounted) return;

    var shown = wordBreakdown;
    var spelling = const <SpellingBreakdown?>[];
    if (shown != null && spellingIndex != null) {
      (shown, spelling) = _alignedWithSpelling(shown, thaiWord, spellingIndex);
    }

    return showDialog<void>(
      context: context,
      builder: (context) => ToneExplanationDialog(
        thaiWord: thaiWord,
        analysis: analysis,
        wordBreakdown: shown,
        spelling: spelling,
      ),
    );
  }
}
