import 'package:flutter_test/flutter_test.dart';
import 'package:thai_memo/core/thai_tone_analyzer.dart';
import 'package:thai_memo/data/models/syllable.dart';
import 'package:thai_memo/data/models/word_breakdown.dart';
import 'package:thai_memo/domain/sentence_tone_spans.dart';

Syllable _syllable(String tone) => Syllable(
      text: 'x',
      initialConsonant: 'x',
      consonantClass: 'middle',
      tone: tone,
      toneMark: 'none',
      syllableType: 'live',
    );

WordBreakdown _word(String text, List<String>? tones) => WordBreakdown(
      wordText: text,
      pronunciation: '',
      meaning: '',
      syllables: tones?.map(_syllable).toList(),
    );

void main() {
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
}
