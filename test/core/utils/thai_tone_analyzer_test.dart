import 'package:flutter_test/flutter_test.dart';
import 'package:thai_memo/core/thai_tone_analyzer.dart';

void main() {
  group('ThaiToneAnalyzer - Consonant Coverage', () {
    test('should cover all 44 Thai consonants', () {
      final totalConsonants = ThaiToneAnalyzer.highConsonants.length +
          ThaiToneAnalyzer.middleConsonants.length +
          ThaiToneAnalyzer.lowConsonants.length;

      expect(totalConsonants, equals(46)); // 44 + 2 obsolete (ฃ, ฅ)
    });

    test('should have correct number of high consonants', () {
      expect(ThaiToneAnalyzer.highConsonants.length, equals(11));
    });

    test('should have correct number of middle consonants', () {
      expect(ThaiToneAnalyzer.middleConsonants.length, equals(9));
    });

    test('should have correct number of low consonants', () {
      expect(ThaiToneAnalyzer.lowConsonants.length, equals(26));
    });
  });

  group('ThaiToneAnalyzer - Consonant Class Detection', () {
    test('high consonants should be detected correctly', () {
      final highConsonants = ['ข', 'ฉ', 'ฐ', 'ถ', 'ผ', 'ฝ', 'ศ', 'ษ', 'ส', 'ห'];

      for (final consonant in highConsonants) {
        final analysis = ThaiToneAnalyzer.analyzeTone(consonant);
        expect(
          analysis.consonantClass,
          equals(ConsonantClass.high),
          reason: '$consonant should be high consonant',
        );
      }
    });

    test('middle consonants should be detected correctly', () {
      final middleConsonants = ['ก', 'จ', 'ฎ', 'ฏ', 'ด', 'ต', 'บ', 'ป', 'อ'];

      for (final consonant in middleConsonants) {
        final analysis = ThaiToneAnalyzer.analyzeTone(consonant);
        expect(
          analysis.consonantClass,
          equals(ConsonantClass.middle),
          reason: '$consonant should be middle consonant',
        );
      }
    });

    test('low consonants should be detected correctly', () {
      final lowConsonants = [
        'ค', 'ง', 'ช', 'ซ', 'ท', 'ธ', 'น', 'พ', 'ฟ', 'ภ', 'ม', 'ย', 'ร', 'ล', 'ว', 'ฮ',
        'ฑ', 'ฒ', 'ณ', 'ฤ', 'ฦ', 'ฌ', 'ญ', 'ฆ', 'ฬ',
      ];

      for (final consonant in lowConsonants) {
        final analysis = ThaiToneAnalyzer.analyzeTone(consonant);
        expect(
          analysis.consonantClass,
          equals(ConsonantClass.low),
          reason: '$consonant should be low consonant',
        );
      }
    });
  });

  group('ThaiToneAnalyzer - Tone Mark Detection', () {
    test('should detect mai ek (่)', () {
      final analysis = ThaiToneAnalyzer.analyzeTone('ก่า');
      expect(analysis.toneMark, equals(ToneMark.maiEk));
    });

    test('should detect mai tho (้)', () {
      final analysis = ThaiToneAnalyzer.analyzeTone('ก้า');
      expect(analysis.toneMark, equals(ToneMark.maiTho));
    });

    test('should detect mai tri (๊)', () {
      final analysis = ThaiToneAnalyzer.analyzeTone('ก๊า');
      expect(analysis.toneMark, equals(ToneMark.maiTri));
    });

    test('should detect mai chattawa (๋)', () {
      final analysis = ThaiToneAnalyzer.analyzeTone('ก๋า');
      expect(analysis.toneMark, equals(ToneMark.maiChattawa));
    });

    test('should detect no tone mark', () {
      final analysis = ThaiToneAnalyzer.analyzeTone('กา');
      expect(analysis.toneMark, equals(ToneMark.none));
    });
  });

  group('ThaiToneAnalyzer - Syllable Type Detection', () {
    test('should detect live syllable (long vowel)', () {
      final analysis = ThaiToneAnalyzer.analyzeTone('กา');
      expect(analysis.syllableType, equals(SyllableType.live));
    });

    test('should detect live syllable (ending with -m)', () {
      final analysis = ThaiToneAnalyzer.analyzeTone('กาม');
      expect(analysis.syllableType, equals(SyllableType.live));
    });

    test('should detect dead syllable (short vowel)', () {
      final analysis = ThaiToneAnalyzer.analyzeTone('กะ');
      expect(analysis.syllableType, equals(SyllableType.dead));
    });

    test('should detect dead syllable (ending with -k)', () {
      final analysis = ThaiToneAnalyzer.analyzeTone('กาก');
      expect(analysis.syllableType, equals(SyllableType.dead));
    });
  });

  group('ThaiToneAnalyzer - Tone Rules', () {
    // 中子音のテスト
    test('middle consonant + no mark + live → mid tone', () {
      final analysis = ThaiToneAnalyzer.analyzeTone('กา');
      expect(analysis.resultingTone, equals(ThaiTone.mid));
    });

    test('middle consonant + no mark + dead → low tone', () {
      final analysis = ThaiToneAnalyzer.analyzeTone('กะ');
      expect(analysis.resultingTone, equals(ThaiTone.low));
    });

    test('middle consonant + mai ek + live → low tone', () {
      final analysis = ThaiToneAnalyzer.analyzeTone('ก่า');
      expect(analysis.resultingTone, equals(ThaiTone.low));
    });

    test('middle consonant + mai tho + live → falling tone', () {
      final analysis = ThaiToneAnalyzer.analyzeTone('ก้า');
      expect(analysis.resultingTone, equals(ThaiTone.falling));
    });

    test('middle consonant + mai tri + live → high tone', () {
      final analysis = ThaiToneAnalyzer.analyzeTone('ก๊า');
      expect(analysis.resultingTone, equals(ThaiTone.high));
    });

    test('middle consonant + mai chattawa + live → rising tone', () {
      final analysis = ThaiToneAnalyzer.analyzeTone('ก๋า');
      expect(analysis.resultingTone, equals(ThaiTone.rising));
    });

    // 高子音のテスト
    test('high consonant + no mark + live → rising tone', () {
      final analysis = ThaiToneAnalyzer.analyzeTone('ขา');
      expect(analysis.resultingTone, equals(ThaiTone.rising));
    });

    test('high consonant + no mark + dead → low tone', () {
      final analysis = ThaiToneAnalyzer.analyzeTone('ขะ');
      expect(analysis.resultingTone, equals(ThaiTone.low));
    });

    test('high consonant + mai ek + live → low tone', () {
      final analysis = ThaiToneAnalyzer.analyzeTone('ข่า');
      expect(analysis.resultingTone, equals(ThaiTone.low));
    });

    test('high consonant + mai tho + live → falling tone', () {
      final analysis = ThaiToneAnalyzer.analyzeTone('ข้า');
      expect(analysis.resultingTone, equals(ThaiTone.falling));
    });

    // 低子音のテスト
    test('low consonant + no mark + live → mid tone', () {
      final analysis = ThaiToneAnalyzer.analyzeTone('คา');
      expect(analysis.resultingTone, equals(ThaiTone.mid));
    });

    test('low consonant + no mark + dead (short vowel) → high tone', () {
      final analysis = ThaiToneAnalyzer.analyzeTone('คะ');
      expect(analysis.resultingTone, equals(ThaiTone.high));
    });

    test('low consonant + no mark + dead (long vowel) → falling tone', () {
      final analysis = ThaiToneAnalyzer.analyzeTone('คาก');
      expect(analysis.resultingTone, equals(ThaiTone.falling));
    });

    test('low consonant + mai ek + live → falling tone', () {
      final analysis = ThaiToneAnalyzer.analyzeTone('ค่า');
      expect(analysis.resultingTone, equals(ThaiTone.falling));
    });

    test('low consonant + mai tho + live → high tone', () {
      final analysis = ThaiToneAnalyzer.analyzeTone('ค้า');
      expect(analysis.resultingTone, equals(ThaiTone.high));
    });
  });
}
