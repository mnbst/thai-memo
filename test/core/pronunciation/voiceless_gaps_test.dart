import 'package:flutter_test/flutter_test.dart';
import 'package:thai_memo/core/pronunciation/pronunciation_analyzer.dart';

List<bool> _voiced(String pattern) =>
    pattern.split('').map((c) => c == 'v').toList();

void main() {
  group('findVoicelessGaps', () {
    test('声の途切れを [開始, 終了] で拾う', () {
      // vvv...vvv...vv → 3-5 と 9-11 が途切れ
      expect(_gaps('vvv...vvv...vv'), [
        [3, 5],
        [9, 11],
      ]);
    });

    test('短い途切れは子音の証拠にならないので落とす', () {
      // 2フレーム（20ms）は閉鎖音の閉鎖区間より短い。
      expect(_gaps('vvv..vvv'), isEmpty);
    });

    test('末尾で終わる途切れも拾う', () {
      expect(_gaps('vvv...'), [
        [3, 5],
      ]);
    });

    test('先頭から始まる途切れも拾う', () {
      expect(_gaps('...vvv'), [
        [0, 2],
      ]);
    });

    test('全て有声なら空', () {
      expect(_gaps('vvvvv'), isEmpty);
    });

    test('空の入力を受けても落ちない', () {
      expect(findVoicelessGaps(const []), isEmpty);
    });
  });
}

List<List<int>> _gaps(String pattern) => findVoicelessGaps(_voiced(pattern));
