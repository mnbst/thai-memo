import 'package:flutter_test/flutter_test.dart';
import 'package:thai_memo/presentation/widgets/vocab_cap_sheet.dart';

void main() {
  group('VocabCapSheet.isDue', () {
    final now = DateTime(2026, 11, 26, 12);
    int ago(Duration d) => now.subtract(d).millisecondsSinceEpoch;

    test('未表示なら出す', () {
      expect(VocabCapSheet.isDue(null, now), isTrue);
    });

    test('間隔未満なら出さない', () {
      expect(VocabCapSheet.isDue(ago(const Duration(days: 2, hours: 23)), now),
          isFalse);
    });

    test('間隔を過ぎたら出す', () {
      expect(
          VocabCapSheet.isDue(ago(VocabCapSheet.reshowInterval), now), isTrue);
    });

    test('前回が未来（時計が戻った）なら出す', () {
      expect(VocabCapSheet.isDue(ago(const Duration(days: -1)), now), isTrue);
    });
  });
}
