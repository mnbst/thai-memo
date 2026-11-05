// =============================================================================
// spelling_breakdown_view.dart
// 綴りの分解の表示。字を書く順にマスで並べる（SpellingPartsRow）のと、声調の
// 決まり方（SpellingToneRuleTile）。クイズの答え合わせ・声調ダイアログ・復習の
// 語の詳細で共用する。
// =============================================================================

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/config/app_config.dart';
import '../../core/spelling_breakdown.dart';
import '../../core/thai_tone_analyzer.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/quiz_question.dart';
import '../../l10n/app_localizations.dart';
import '../screens/tone_guide_screen.dart';
import 'tone_shift_table.dart';

/// 部品ごとの色。深藍の面でも紙の面でも読める明度に振り分ける。
Color _roleColor(String role, bool dark) {
  return switch (role) {
    'onset' => dark ? const Color(0xFF8FB4F0) : const Color(0xFF2F5AA8),
    'vowel' => dark ? const Color(0xFFE2BE76) : AppColors.goldInk,
    'coda' => dark ? const Color(0xFF74C4A8) : AppColors.jade,
    // 読まない字は音が無いので、色を持たせず沈めておく。
    'silent' => dark ? const Color(0xFF8A8F9E) : const Color(0xFF7A7F8C),
    _ => dark ? const Color(0xFFCB9BDD) : const Color(0xFF8A4FA0),
  };
}

ThaiTone _toneOf(String tone) => switch (tone) {
      'low' => ThaiTone.low,
      'falling' => ThaiTone.falling,
      'high' => ThaiTone.high,
      'rising' => ThaiTone.rising,
      _ => ThaiTone.mid,
    };

ConsonantClass _classOf(String value) => switch (value) {
      'mid' => ConsonantClass.middle,
      'high' => ConsonantClass.high,
      _ => ConsonantClass.low,
    };

ToneMark _markOf(String value) => switch (value) {
      '่' => ToneMark.maiEk,
      '้' => ToneMark.maiTho,
      '๊' => ToneMark.maiTri,
      '๋' => ToneMark.maiChattawa,
      _ => ToneMark.none,
    };

/// 声調名と、その下に上げ下げの記号を中央揃えで出す。
class ToneNameWithSymbol extends StatelessWidget {
  final ThaiTone tone;
  final TextStyle? nameStyle;

  /// 省略すると名前と同じ見た目。
  final TextStyle? symbolStyle;

  const ToneNameWithSymbol({
    super.key,
    required this.tone,
    this.nameStyle,
    this.symbolStyle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          tone.displayName(L10n.of(context)),
          textAlign: TextAlign.center,
          style: nameStyle,
        ),
        Text(
          tone.symbol,
          textAlign: TextAlign.center,
          style: (symbolStyle ?? nameStyle ?? const TextStyle()).copyWith(
            fontFamily: 'monospace',
            height: 1.1,
          ),
        ),
      ],
    );
  }
}

/// 分解カードの1マス。役割・見出し・字・読み。
class _BreakdownCell {
  final String role;
  final String label;
  final String glyph;
  final String value;

  /// 声調のマスだけ持つ。名前と記号の2段で出す。
  final ThaiTone? tone;

  /// 頭子音のマスだけ持つ。子音の階級（低子音など）。
  final String? consonantClass;

  const _BreakdownCell({
    required this.role,
    required this.label,
    required this.glyph,
    this.value = '',
    this.tone,
    this.consonantClass,
  });
}

/// 綴りが何に当たるかを、書く順にマスで並べる。
///
/// 綴りそのものは1つの Text のまま別に出す（部品ごとに Text を割ると、母音記号や
/// 声調記号が土台の子音から外れて崩れる）。
class SpellingPartsRow extends StatelessWidget {
  final List<SpellingPart> parts;
  final List<SpellingGlyph> glyphs;

  /// 渡すと頭子音のマスに子音の階級を添える。
  final SpellingToneRule? toneRule;

  /// マスの字の大きさ。箱の高さはこの1.5倍で、上下に付く記号まで収める。
  final double glyphSize;

  const SpellingPartsRow({
    super.key,
    required this.parts,
    required this.glyphs,
    this.toneRule,
    this.glyphSize = 32,
  });

  String _roleLabel(L10n l10n, String role) => switch (role) {
        'onset' => l10n.quizPartOnset,
        'vowel' => l10n.quizPartVowel,
        'coda' => l10n.quizPartCoda,
        _ => l10n.quizPartToneLabel,
      };

  /// 表示するセルを作る。書く順に並べ、母音字が末子音を兼ねる綴り
  /// （ทำ の ำ = am、ไม่ の ไ = ai）は1つのセットとして1マスにまとめる。
  List<_BreakdownCell> _cells(L10n l10n) {
    final ordered = _inWritingOrder();
    final coda = parts.firstWhere((p) => p.role == 'coda',
        orElse: () => const SpellingPart(role: 'coda'));
    // 末子音に字が無く、母音の字がそれを兼ねているとき（母音に字がある）。
    final vowel = parts.firstWhere((p) => p.role == 'vowel',
        orElse: () => const SpellingPart(role: 'vowel'));
    final merged =
        coda.text.isEmpty && coda.sound.isNotEmpty && vowel.text.isNotEmpty;

    final cells = <_BreakdownCell>[];
    for (final part in ordered) {
      if (merged && part.role == 'coda') continue;
      if (merged && part.role == 'vowel') {
        cells.add(_BreakdownCell(
          role: 'vowel',
          label: l10n.quizPartVowelCoda,
          glyph: part.displayText,
          value: '${part.sound}${coda.sound}',
        ));
        continue;
      }
      cells.add(_BreakdownCell(
        // 読まない字の見出しは記号の名前。記号そのもの（์）は単体だと
        // 土台が無くて豆腐になるので出さない。
        label: part.role == 'silent'
            ? (part.text.contains('์')
                ? l10n.quizPartKaran
                : l10n.quizPartSilent)
            : _roleLabel(l10n, part.role),
        role: part.role,
        glyph: part.displayText,
        value: switch (part.role) {
          // 読まない字（องค์ の ค์、จันทร์ の ทร์）は音を持たない。
          'silent' => l10n.quizPartSilentValue,
          'tone' => '',
          _ => part.sound.isEmpty ? l10n.quizPartNone : part.sound,
        },
        tone: part.role == 'tone' ? _toneOf(part.tone) : null,
        consonantClass: part.role == 'onset' && toneRule != null
            ? _classOf(toneRule!.consonantClass).displayName(l10n)
            : null,
      ));
    }
    return cells;
  }

  /// 部品を綴りを書く順に並べ替える。
  ///
  /// 字を持たない部品（書かない母音・母音字が兼ねる末子音）は書く位置が
  /// 無いので、音の並び（頭子音→母音→末子音→声調→読まない字）で
  /// 前後の部品の間に入れる。末尾に寄せると คน の母音が末子音より後ろに
  /// 来て、読みの順と食い違う。
  List<SpellingPart> _inWritingOrder() {
    if (glyphs.isEmpty) return parts;
    const soundOrder = ['onset', 'vowel', 'coda', 'tone', 'silent'];
    final writtenAt = <String, double>{};
    for (var i = 0; i < glyphs.length; i++) {
      writtenAt.putIfAbsent(glyphs[i].role, () => i.toDouble());
    }

    final sorted = [...parts]..sort((a, b) =>
        soundOrder.indexOf(a.role).compareTo(soundOrder.indexOf(b.role)));
    final keys = <String, double>{};
    var prev = -1.0;
    for (var i = 0; i < sorted.length; i++) {
      final role = sorted[i].role;
      var key = writtenAt[role];
      if (key == null) {
        // 次に字を持つ部品の位置との間に置く。
        var next = glyphs.length.toDouble();
        for (var j = i + 1; j < sorted.length; j++) {
          final at = writtenAt[sorted[j].role];
          if (at != null) {
            next = at;
            break;
          }
        }
        key = (prev + next) / 2;
      }
      keys[role] = key;
      prev = key;
    }
    sorted.sort((a, b) => keys[a.role]!.compareTo(keys[b.role]!));
    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final cells = _cells(L10n.of(context));
    // セルは高さを揃えて、役割ラベルと読みが同じ行に並ぶようにする。
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < cells.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(child: _partCell(context, cells[i], dark)),
          ],
        ],
      ),
    );
  }

  Widget _partCell(BuildContext context, _BreakdownCell cell, bool dark) {
    final theme = Theme.of(context);
    final color = _roleColor(cell.role, dark);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: dark ? 0.16 : 0.07),
        borderRadius: BorderRadius.circular(AppConfig.cardBorderRadius),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 字の高さは綴りによって変わる（声調記号が乗る・乗らない）ので、
          // 箱で固定して下のラベルを揃える。字にならない部品は — で示す。
          SizedBox(
            height: MediaQuery.textScalerOf(context).scale(glyphSize * 1.5),
            child: Center(
              // เ-ือ のように長い字はマスに収まるまで縮める。
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  cell.glyph.isEmpty ? '—' : cell.glyph,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: glyphSize,
                    fontWeight: FontWeight.w500,
                    color: cell.glyph.isEmpty
                        ? theme.colorScheme.outlineVariant
                        : color,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          // 読まない字が増えると5マスになるので、はみ出す前に縮める。
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              cell.label,
              maxLines: 1,
              style: theme.textTheme.labelSmall?.copyWith(
                fontSize: 13,
                color: color,
              ),
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Builder(builder: (context) {
              final style = theme.textTheme.titleSmall?.copyWith(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface,
              );
              final tone = cell.tone;
              if (tone != null) {
                return ToneNameWithSymbol(
                  tone: tone,
                  nameStyle: style,
                  symbolStyle: style?.copyWith(fontSize: 18),
                );
              }
              return Text(
                cell.value,
                textAlign: TextAlign.center,
                style: style,
              );
            }),
          ),
          if (cell.consonantClass case final klass?) ...[
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                klass,
                maxLines: 1,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontSize: 13,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 声調は字1つに対応しないので、決まり方（階級 × 生音/死音 × 記号）を
/// 1行で見せる。開くと、その階級の声調表を該当行を光らせて出す。
/// 表そのものは声調ガイドと同じ ThaiToneAnalyzer から引く。
class SpellingToneRuleTile extends StatelessWidget {
  final List<SpellingPart> parts;
  final SpellingToneRule rule;

  const SpellingToneRuleTile({
    super.key,
    required this.parts,
    required this.rule,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    final color = _roleColor('tone', theme.brightness == Brightness.dark);
    final klass = _classOf(rule.consonantClass);
    final mark = _markOf(rule.mark);
    final syllable =
        rule.syllable == 'dead' ? SyllableType.dead : SyllableType.live;
    final toneName = parts
        .firstWhere((p) => p.role == 'tone',
            orElse: () => const SpellingPart(role: 'tone'))
        .tone;
    final tone = _toneOf(toneName);
    // 表の行と読みが違う語では、行を強調すると声調が食い違って見える。
    final isException = toneName.isNotEmpty &&
        ToneShiftTable.isException(
          consonantClass: klass,
          toneMark: mark,
          syllableType: syllable,
          tone: tone,
          hasShortVowel: rule.shortVowel,
        );

    return Theme(
      // 区切り線を消して、カードの中の表に見えるようにする。
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: const ValueKey('quiz_spelling_tone_rule'),
        tilePadding: const EdgeInsets.symmetric(horizontal: 14),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConfig.cardBorderRadius),
          side: BorderSide(color: color.withValues(alpha: 0.4)),
        ),
        collapsedShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConfig.cardBorderRadius),
          side: BorderSide(color: color.withValues(alpha: 0.4)),
        ),
        title: Text(
          l10n.quizToneRuleFor(klass.displayName(l10n)),
          style: theme.textTheme.bodyMedium?.copyWith(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
        // この語がどの行に当たるかは畳んだままでも読めるようにする。
        // 語の途中で折り返さないよう、区切りごとに分けて並べる。
        subtitle: DefaultTextStyle.merge(
          style: theme.textTheme.bodySmall?.copyWith(
            fontSize: 14,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          child: Wrap(
            spacing: 4,
            children: [
              Text(syllable.displayName(l10n)),
              Text('× ${mark.displayName(l10n)}'),
              Text('→ ${tone.displayName(l10n)}'),
              if (isException) Text(l10n.toneRuleException),
            ],
          ),
        ),
        children: [
          ToneShiftTable(
            consonantClass: klass,
            toneMark: isException ? null : mark,
            syllableType: syllable,
            hasShortVowel: rule.shortVowel,
          ),
          const SizedBox(height: 8),
          // 表だけで足りないときは声調ガイドへ送る。
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              key: const ValueKey('quiz_spelling_tone_guide_button'),
              onPressed: () => Navigator.push(
                context,
                CupertinoPageRoute(
                  settings:
                      const RouteSettings(name: ToneGuideScreen.routeName),
                  builder: (context) => const ToneGuideScreen(),
                ),
              ),
              icon: const Icon(Icons.school),
              label: Text(l10n.toneLearnMore),
            ),
          ),
        ],
      ),
    );
  }
}

/// 復習の語の詳細に出す綴りの分解。分解できる音節が無い語では何も出さない。
class WordSpellingSection extends StatelessWidget {
  final String word;
  final List<String> syllables;

  const WordSpellingSection({
    super.key,
    required this.word,
    required this.syllables,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<SpellingIndex>(
      future: SpellingIndex.load(),
      builder: (context, snapshot) {
        final items = snapshot.data?.forWord(word, syllables) ?? const [];
        if (items.isEmpty) return const SizedBox.shrink();

        final theme = Theme.of(context);
        final cs = theme.colorScheme;
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 6),
                child: Text(
                  L10n.of(context).quizSpellingBreakdown,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
              Material(
                color: cs.surface,
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < items.length; i++) ...[
                        if (i > 0) const Divider(height: 24),
                        // 語そのものを分解したときは上に出ているので繰り返さない。
                        if (items[i].text != word) ...[
                          Text(
                            items[i].text,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 6),
                        ],
                        SpellingPartsRow(
                          parts: items[i].breakdown.parts,
                          glyphs: items[i].breakdown.glyphs,
                          toneRule: items[i].breakdown.toneRule,
                        ),
                        if (items[i].breakdown.toneRule case final rule?) ...[
                          const SizedBox(height: 8),
                          SpellingToneRuleTile(
                            parts: items[i].breakdown.parts,
                            rule: rule,
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
