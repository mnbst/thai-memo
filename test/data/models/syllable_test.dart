// =============================================================================
// syllable_test.dart
// parseSyllables の回帰テスト。
//
// サーバー（nlp.segment_syllables）は音節を文字列の配列で返すため、
// Syllable.fromJson をそのまま適用すると型エラーになる。この境界を守る。
// =============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:thai_memo/data/models/syllable.dart';

void main() {
  group('parseSyllables', () {
    test('サーバー由来の文字列配列を Syllable に変換する', () {
      final result = parseSyllables(['มา']);

      expect(result, isNotNull);
      expect(result!.length, 1);
      expect(result.first.text, 'มา');
    });

    test('文字列から声調を解析して埋める', () {
      final result = parseSyllables(['มา'])!;
      final syllable = result.first;

      // 解析できたかどうかだけを見る。声調判定そのものは
      // thai_tone_analyzer_test.dart の担当。
      expect(syllable.initialConsonant, isNotEmpty);
      expect(syllable.consonantClass, isNotEmpty);
      expect(syllable.tone, isNotEmpty);
      expect(syllable.syllableType, isNotEmpty);
    });

    test('複数音節をすべて変換する', () {
      final result = parseSyllables(['สวัส', 'ดี'])!;

      expect(result.map((s) => s.text).toList(), ['สวัส', 'ดี']);
    });

    test('SQLite 由来の Map 形式も受け取れる', () {
      final result = parseSyllables([
        {
          'text': 'ดี',
          'initial_consonant': 'ด',
          'consonant_class': 'middle',
          'tone': 'mid',
          'tone_mark': 'none',
          'syllable_type': 'live',
        }
      ])!;

      expect(result.first.text, 'ดี');
      expect(result.first.consonantClass, 'middle');
      expect(result.first.tone, 'mid');
    });

    test('文字列と Map が混在していても両方変換する', () {
      final result = parseSyllables([
        'มา',
        {
          'text': 'ดี',
          'initial_consonant': 'ด',
          'consonant_class': 'middle',
          'tone': 'mid',
          'tone_mark': 'none',
          'syllable_type': 'live',
        },
      ])!;

      expect(result.length, 2);
      expect(result.map((s) => s.text).toList(), ['มา', 'ดี']);
    });

    test('想定外の型は例外にせず取り除く', () {
      final result = parseSyllables(['มา', 42, null])!;

      expect(result.length, 1);
      expect(result.first.text, 'มา');
    });

    test('null は null のまま返す', () {
      expect(parseSyllables(null), isNull);
    });

    test('空配列は空リストになる', () {
      expect(parseSyllables([]), isEmpty);
    });
  });
}
