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
        'ค',
        'ง',
        'ช',
        'ซ',
        'ท',
        'ธ',
        'น',
        'พ',
        'ฟ',
        'ภ',
        'ม',
        'ย',
        'ร',
        'ล',
        'ว',
        'ฮ',
        'ฑ',
        'ฒ',
        'ณ',
        'ฤ',
        'ฦ',
        'ฌ',
        'ญ',
        'ฆ',
        'ฬ',
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

  group('ThaiToneAnalyzer - ณ ล ฬ as Live End Consonants (/n/ sound)', () {
    test('คุณ: low class + short vowel + ณ(live) → mid tone', () {
      final analysis = ThaiToneAnalyzer.analyzeTone('คุณ');
      expect(analysis.syllableType, equals(SyllableType.live),
          reason: 'ณ は末子音として /n/ の音 → 生音節');
      expect(analysis.resultingTone, equals(ThaiTone.mid));
    });

    test('ศาล: high class + long vowel + ล(live) → rising tone', () {
      final analysis = ThaiToneAnalyzer.analyzeTone('ศาล');
      expect(analysis.syllableType, equals(SyllableType.live),
          reason: 'ล は末子音として /n/ の音 → 生音節');
      expect(analysis.resultingTone, equals(ThaiTone.rising));
    });
  });

  group('ThaiToneAnalyzer - ว as Compound Vowel อัว', () {
    test('ควร: low class + live (ว=อัว, ร=final) → mid tone', () {
      final analysis = ThaiToneAnalyzer.analyzeTone('ควร');
      expect(analysis.syllableType, equals(SyllableType.live),
          reason: 'ร は生音節末子音');
      expect(analysis.hasShortVowel, isFalse, reason: 'อัว は長複合母音');
      expect(analysis.resultingTone, equals(ThaiTone.mid));
    });

    test('ควบ: low class + dead (ว=อัว long) → falling tone', () {
      final analysis = ThaiToneAnalyzer.analyzeTone('ควบ');
      expect(analysis.syllableType, equals(SyllableType.dead));
      expect(analysis.hasShortVowel, isFalse, reason: 'อัว は長複合母音のため下降声');
      expect(analysis.resultingTone, equals(ThaiTone.falling));
    });

    test('กวน: middle class + live (ว=อัว) → mid tone', () {
      final analysis = ThaiToneAnalyzer.analyzeTone('กวน');
      expect(analysis.syllableType, equals(SyllableType.live));
      expect(analysis.resultingTone, equals(ThaiTone.mid));
    });
  });

  group('ThaiToneAnalyzer - รร as Short Vowel /a/', () {
    test('กรรม: middle class + live (รร=short /a/, ม=final) → mid tone', () {
      final analysis = ThaiToneAnalyzer.analyzeTone('กรรม');
      expect(analysis.syllableType, equals(SyllableType.live));
      expect(analysis.hasShortVowel, isTrue, reason: 'รร は短母音 /a/');
      expect(analysis.resultingTone, equals(ThaiTone.mid));
    });

    test('พรรค: low class + dead (รร=short /a/, ค=final) → high tone', () {
      final analysis = ThaiToneAnalyzer.analyzeTone('พรรค');
      expect(analysis.syllableType, equals(SyllableType.dead));
      expect(analysis.hasShortVowel, isTrue);
      expect(analysis.resultingTone, equals(ThaiTone.high));
    });

    test('สรร: high class + live (ร=final) → rising tone', () {
      final analysis = ThaiToneAnalyzer.analyzeTone('สรร');
      expect(analysis.syllableType, equals(SyllableType.live),
          reason: 'ร は生音節末子音（/n/音）');
      expect(analysis.resultingTone, equals(ThaiTone.rising));
    });
  });

  group('ThaiToneAnalyzer - Compound Vowel Constants', () {
    test('ตัว: explicit ัว = long compound vowel → hasShortVowel=false', () {
      final analysis = ThaiToneAnalyzer.analyzeTone('ตัว');
      expect(analysis.hasShortVowel, isFalse,
          reason: 'ัว は長複合母音（ั 単独は短母音だが ัว は長い）');
      expect(analysis.syllableType, equals(SyllableType.live));
    });

    test('ไป: ไ = /ai/ compound vowel → hasShortVowel=false, mid tone', () {
      final analysis = ThaiToneAnalyzer.analyzeTone('ไป');
      expect(analysis.hasShortVowel, isFalse);
      expect(analysis.resultingTone, equals(ThaiTone.mid));
    });

    test('ใจ: ใ = /ai/ compound vowel → hasShortVowel=false', () {
      final analysis = ThaiToneAnalyzer.analyzeTone('ใจ');
      expect(analysis.hasShortVowel, isFalse);
    });
  });

  group('ThaiToneAnalyzer - Tone Exceptions', () {
    test('เยอะ: exception → high tone', () {
      final analysis = ThaiToneAnalyzer.analyzeTone('เยอะ');
      expect(analysis.resultingTone, equals(ThaiTone.high));
    });
  });
}
