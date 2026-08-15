import 'package:flutter_test/flutter_test.dart';
import 'package:thai_memo/core/thai_tone_analyzer.dart';
import 'package:thai_memo/data/models/syllable.dart';
import 'package:thai_memo/data/models/word_breakdown.dart';
import 'package:thai_memo/domain/sentence_tone_spans.dart';

Syllable _syllable(
  String tone, {
  bool? shortVowel,
  String syllableType = 'live',
}) =>
    Syllable(
      text: 'x',
      initialConsonant: 'x',
      consonantClass: 'middle',
      tone: tone,
      toneMark: 'none',
      syllableType: syllableType,
      hasShortVowel: shortVowel,
    );

WordBreakdown _word(String text, List<String>? tones) => WordBreakdown(
      wordText: text,
      pronunciation: '',
      meaning: '',
      syllables: tones?.map((t) => _syllable(t)).toList(),
    );

WordBreakdown _wordWith(String text, List<Syllable> syllables) =>
    WordBreakdown(
      wordText: text,
      pronunciation: '',
      meaning: '',
      syllables: syllables,
    );

WordBreakdown _wordWithPronunciation(
  String text,
  String pronunciation,
  List<String> tones,
) =>
    WordBreakdown(
      wordText: text,
      pronunciation: pronunciation,
      meaning: '',
      syllables: tones.map((t) => _syllable(t)).toList(),
    );

void main() {
  group('buildSentenceToneSpans - 音節ごとのローマ字', () {
    test('音節数と一致すれば音節へ割り当てる', () {
      final spans = buildSentenceToneSpans([
        _wordWithPronunciation('สวัสดี', 'sa-wàt-dii', ['mid', 'low', 'mid']),
      ]);

      expect(spans.syllableRomans, ['sa', 'wàt', 'dii']);
    });

    test('音節数が食い違う語では出さない', () {
      final spans = buildSentenceToneSpans([
        _wordWithPronunciation('สวัสดี', 'sa-wàt', ['mid', 'low', 'mid']),
      ]);

      expect(spans.syllableRomans, ['', '', '']);
    });

    test('発音表記が無い語では出さない', () {
      final spans = buildSentenceToneSpans([
        _word('มา', ['mid']),
      ]);

      expect(spans.syllableRomans, ['']);
    });

    test('語をまたいで音節順に連なる', () {
      final spans = buildSentenceToneSpans([
        _wordWithPronunciation('ผม', 'phǒm', ['rising']),
        _wordWithPronunciation('สวัสดี', 'sa-wàt-dii', ['mid', 'low', 'mid']),
      ]);

      expect(spans.syllableRomans, ['phǒm', 'sa', 'wàt', 'dii']);
    });
  });

  group('buildSentenceToneSpans', () {
    test('語順に音節の声調を連結する', () {
      final spans = buildSentenceToneSpans([
        _word('มา', ['mid']),
        _word('อาหาร', ['mid', 'rising']),
      ]);

      expect(spans.tones, [ThaiTone.mid, ThaiTone.mid, ThaiTone.rising]);
    });

    test('語ごとの音節範囲を持つ', () {
      final spans = buildSentenceToneSpans([
        _word('มา', ['mid']),
        _word('อาหาร', ['mid', 'rising']),
      ]);

      expect(spans.words.length, 2);
      expect(spans.words[0].start, 0);
      expect(spans.words[0].length, 1);
      expect(spans.words[1].start, 1);
      expect(spans.words[1].length, 2);
      expect(spans.words[1].end, 3);
    });

    test('音節データが無い語は飛ばす', () {
      // 音節を返さなかった古い例文が混ざっても、残りの語で練習できる。
      final spans = buildSentenceToneSpans([
        _word('มา', ['mid']),
        _word('ไทย', null),
        _word('ดี', ['mid']),
      ]);

      expect(spans.words.map((w) => w.wordText), ['มา', 'ดี']);
      expect(spans.tones.length, 2);
      // 飛ばした語のぶん位置がずれない。
      expect(spans.words[1].start, 1);
    });

    test('未知の声調名は unknown に落ちる', () {
      final spans = buildSentenceToneSpans([
        _word('x', ['unknown']),
        _word('y', ['nonsense']),
      ]);

      expect(spans.tones, [ThaiTone.unknown, ThaiTone.unknown]);
    });

    test('音節が1つも無ければ空', () {
      expect(buildSentenceToneSpans([]).isEmpty, isTrue);
      expect(buildSentenceToneSpans([_word('x', null)]).isEmpty, isTrue);
    });

    test('短母音と死音節に印を付ける', () {
      // 短い音節は声調の動きを出しきれないので、形ではなく高低差で判断する。
      final spans = buildSentenceToneSpans([
        _wordWith('x', [
          _syllable('mid'),
          _syllable('rising', shortVowel: true),
          _syllable('low', syllableType: 'dead'),
        ]),
      ]);

      expect(spans.shortSyllables, [false, true, true]);
    });

    test('contains は語の音節範囲だけ真になる', () {
      final spans = buildSentenceToneSpans([
        _word('มา', ['mid']),
        _word('อาหาร', ['mid', 'rising']),
      ]);

      expect(spans.words[1].contains(0), isFalse);
      expect(spans.words[1].contains(1), isTrue);
      expect(spans.words[1].contains(2), isTrue);
      expect(spans.words[1].contains(3), isFalse);
    });
  });

  group('buildSentenceToneSpans - 節の切れ目', () {
    test('空白の後ろの語の先頭音節が節の頭になる', () {
      final spans = buildSentenceToneSpans(
        [
          _word('ฝนตก', ['rising', 'low']),
          _word('ไปดู', ['mid', 'mid']),
          _word('ไม่ได้', ['falling', 'falling']),
        ],
        thaiText: 'ฝนตก ไปดูไม่ได้',
      );

      expect(spans.clauseStarts, [2]);
    });

    test('空白が無ければ節の切れ目は無い', () {
      final spans = buildSentenceToneSpans(
        [
          _word('ฉัน', ['rising']),
          _word('กิน', ['mid']),
        ],
        thaiText: 'ฉันกิน',
      );

      expect(spans.clauseStarts, isEmpty);
    });

    test('thaiText を渡さなければ1節として扱う', () {
      final spans = buildSentenceToneSpans([
        _word('ฝนตก', ['rising', 'low']),
        _word('ไปดู', ['mid', 'mid']),
      ]);

      expect(spans.clauseStarts, isEmpty);
    });

    test('文頭の空白は切れ目にしない', () {
      final spans = buildSentenceToneSpans(
        [
          _word('ฉัน', ['rising']),
          _word('กิน', ['mid']),
        ],
        thaiText: ' ฉันกิน',
      );

      expect(spans.clauseStarts, isEmpty);
    });

    test('切れ目の直後の語に音節が無ければ、次の語へ持ち越す', () {
      final spans = buildSentenceToneSpans(
        [
          _word('ฝนตก', ['rising', 'low']),
          _word('ไปดู', null),
          _word('ไม่ได้', ['falling', 'falling']),
        ],
        thaiText: 'ฝนตก ไปดูไม่ได้',
      );

      expect(spans.clauseStarts, [2]);
    });
  });
}
