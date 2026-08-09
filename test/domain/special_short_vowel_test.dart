import 'package:flutter_test/flutter_test.dart';
import 'package:thai_memo/core/thai_tone_analyzer.dart';

void main() {
  group('อำ / ไอ / ใอ / เอา は音としては短母音', () {
    // 声調規則の上では生音節なので hasShortVowel は false のまま。
    // 長さ（お手本の時間の取り分）だけがこの判定を必要とする。
    for (final syllable in ['ทำ', 'น้ำ', 'ไป', 'ไทย', 'ใน', 'ใจ', 'เอา', 'เขา', 'เก้า']) {
      test('$syllable は短い', () {
        expect(ThaiToneAnalyzer.hasSpecialShortVowel(syllable), isTrue);
      });
    }
  });

  group('長母音は巻き込まない', () {
    for (final syllable in ['มา', 'นี้', 'ยา', 'งาน', 'กาศ', 'อย่า', 'ฆ่า', 'พูด', 'เมีย', 'เสื้อ', 'แม่']) {
      test('$syllable は長いまま', () {
        expect(ThaiToneAnalyzer.hasSpecialShortVowel(syllable), isFalse);
      });
    }
  });
}
