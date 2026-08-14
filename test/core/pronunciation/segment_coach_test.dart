// 通じなかった語について、子音・母音の直し方を1つだけ選べることを守る。
//
// 音声認識は「通じたか」しか返さないので、**外した音は特定できない**。だから
// ここで守るのは「特定できた」ではなく「その語に含まれる音のうち、日本語話者が
// 最も外しやすいものを1つ、優先順位どおりに選べている」こと。
import 'package:flutter_test/flutter_test.dart';
import 'package:thai_memo/core/pronunciation/segment_coach.dart';
import 'package:thai_memo/core/thai_tone_analyzer.dart';

SegmentSyllable _syllable(String text, String initial, {bool short = false}) =>
    SegmentSyllable(
      text: text,
      initialConsonant: initial,
      hasShortVowel: short,
    );

SegmentPoint? _pointOf(List<SegmentSyllable> syllables) =>
    segmentPointOf(syllables, start: 0, end: syllables.length);

void main() {
  group('末子音の見つけ方', () {
    test('末子音を持つ音節', () {
      expect(ThaiToneAnalyzer.finalConsonantOf('กลาง'), 'ง');
      expect(ThaiToneAnalyzer.finalConsonantOf('งาน'), 'น');
      expect(ThaiToneAnalyzer.finalConsonantOf('ตลาด'), 'ด');
      expect(ThaiToneAnalyzer.finalConsonantOf('ชาติ'), 'ต');
    });

    test('開音節には末子音が無い', () {
      expect(ThaiToneAnalyzer.finalConsonantOf('มา'), '');
      expect(ThaiToneAnalyzer.finalConsonantOf('ค่ะ'), '');
      expect(ThaiToneAnalyzer.finalConsonantOf(''), '');
    });

    test('前置母音の音節で頭子音を末子音と間違えない', () {
      // ไป の ป は頭子音。末子音なら「-p で止める」と誤った助言が出る。
      expect(ThaiToneAnalyzer.finalConsonantOf('ไป'), '');
      expect(ThaiToneAnalyzer.finalConsonantOf('ใจ'), '');
    });

    test('二重子音の2文字目を末子音と間違えない', () {
      expect(ThaiToneAnalyzer.finalConsonantOf('ปลา'), '');
      expect(ThaiToneAnalyzer.finalConsonantOf('ครับ'), 'บ');
    });
  });

  group('優先順位', () {
    test('無気音が他より先に出る', () {
      // ปาก は 無気音 ป と 末子音 -k の両方を持つ。
      final point = _pointOf([_syllable('ปาก', 'ป')]);

      expect(point?.issue, SegmentIssue.unaspirated);
      expect(point?.label, 'ป');
      expect(point?.aspirated, 'พ');
    });

    test('有気音・有声音は無気音の助言に載せない', () {
      // พ は有気音、บ・ด は有声音。日本語のバ・ダがそのまま当たる。
      for (final initial in ['พ', 'ท', 'ค', 'บ', 'ด', 'ม']) {
        final point = _pointOf([_syllable('$initial' 'าน', initial)]);
        expect(
          point?.issue,
          isNot(SegmentIssue.unaspirated),
          reason: initial,
        );
      }
    });

    test('無気音が無ければ末子音の閉鎖音', () {
      final point = _pointOf([_syllable('มาก', 'ม')]);

      expect(point?.issue, SegmentIssue.finalStop);
      expect(point?.sound, 'k');
    });

    test('閉鎖音が無ければ語頭の ง', () {
      final point = _pointOf([_syllable('งาน', 'ง')]);

      expect(point?.issue, SegmentIssue.ngInitial);
    });

    test('語頭の ง が無ければ鼻音の末子音', () {
      final point = _pointOf([_syllable('มาน', 'ม')]);

      expect(point?.issue, SegmentIssue.finalNasal);
      expect(point?.sound, 'n');
    });

    test('末子音が無ければ母音の長短', () {
      final point = _pointOf([_syllable('มะ', 'ม', short: true)]);

      expect(point?.issue, SegmentIssue.shortVowel);
    });

    test('どれも当たらなければ母音の音色', () {
      final point = _pointOf([_syllable('แม', 'ม')]);

      expect(point?.issue, SegmentIssue.thaiVowel);
      expect(point?.vowel, ThaiVowelSound.ae);
    });

    test('出せる点が1つも無ければ出さない', () {
      expect(_pointOf([_syllable('มา', 'ม')]), isNull);
      expect(_pointOf(const []), isNull);
    });

    test('同じ順位なら語の先頭に近い音節', () {
      final point = _pointOf([
        _syllable('มาก', 'ม'),
        _syllable('ดี', 'ด'),
        _syllable('ลาด', 'ล'),
      ]);

      expect(point?.syllableIndex, 0);
    });

    test('語の範囲の外は見ない', () {
      final syllables = [
        _syllable('ปา', 'ป'), // 無気音（範囲外）
        _syllable('มาน', 'ม'), // 鼻音の末子音
      ];
      final point = segmentPointOf(syllables, start: 1, end: 2);

      expect(point?.issue, SegmentIssue.finalNasal);
      expect(point?.syllableIndex, 1);
    });
  });

  group('日本語に無い母音', () {
    test('表記から拾う', () {
      expect(thaiVowelOf('แม'), ThaiVowelSound.ae);
      expect(thaiVowelOf('เธอ'), ThaiVowelSound.oe);
      expect(thaiVowelOf('เดิน'), ThaiVowelSound.oe);
      expect(thaiVowelOf('ตอน'), ThaiVowelSound.aw);
      expect(thaiVowelOf('เกาะ'), ThaiVowelSound.aw);
      expect(thaiVowelOf('มือ'), ThaiVowelSound.ue);
      expect(thaiVowelOf('หนึ่ง'), ThaiVowelSound.ue);
    });

    test('เ◌ือ を เ◌อ（ə）と取り違えない', () {
      expect(thaiVowelOf('เสื้อ'), ThaiVowelSound.ue);
    });

    test('เ◌า は ao の二重母音で、ɔ ではない', () {
      expect(thaiVowelOf('เขา'), isNull);
      expect(thaiVowelOf('เอา'), isNull);
    });

    test('頭子音の อ を母音と取り違えない', () {
      expect(thaiVowelOf('อา'), isNull);
    });

    test('日本語にある母音では出さない', () {
      expect(thaiVowelOf('มา'), isNull);
      expect(thaiVowelOf('ดี'), isNull);
      expect(thaiVowelOf('ดู'), isNull);
    });
  });
}
