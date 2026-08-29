import 'package:flutter_test/flutter_test.dart';
import 'package:thai_memo/core/pronunciation_text.dart';
import 'package:thai_memo/data/models/thai_sentence.dart';
import 'package:thai_memo/data/models/word_breakdown.dart';

void main() {
  group('sanitizePronunciation', () {
    test('TLTKが混入させるバックスラッシュを取り除く', () {
      expect(sanitizePronunciation(r'b\ə̂n'), 'bə̂n');
    });

    test('通常の発音表記はそのまま返す', () {
      expect(sanitizePronunciation('sà-wàt-dii'), 'sà-wàt-dii');
    });
  });

  test('保存済みデータを読み込むときにも取り除かれる', () {
    final word = WordBreakdown(
      wordText: 'เบิ้ล',
      pronunciation: r'b\ə̂n',
      meaning: 'ダブル',
    );
    expect(word.pronunciation, 'bə̂n');

    final sentence = ThaiSentence(
      thaiText: 'แอปเปิ้ล',
      pronunciation: r'ʔɛ̀p-p\ə̂n',
      japaneseTranslation: 'りんご',
      wordBreakdowns: [word],
    );
    expect(sentence.pronunciation, 'ʔɛ̀p-pə̂n');
  });
}
