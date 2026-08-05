import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:thai_memo/presentation/widgets/premium_hint_banner.dart';

void main() {
  group('pickPitch', () {
    test('全ての訴求軸が引かれうる', () {
      final random = Random(1);
      final sources = <String>{
        for (var i = 0; i < 200; i++) pickPitch(random).source,
      };
      expect(sources, hasLength(pitchCount));
      expect(
        sources,
        containsAll(<String>[
          'learning_banner_topic',
          'learning_banner_quality',
          'learning_banner_vocab',
        ]),
      );
    });

    test('配分がおおよそ均等（軸別CTRを比較できる前提）', () {
      final random = Random(42);
      const trials = 3000;
      final counts = <String, int>{};
      for (var i = 0; i < trials; i++) {
        final source = pickPitch(random).source;
        counts[source] = (counts[source] ?? 0) + 1;
      }

      final expected = trials / pitchCount;
      for (final count in counts.values) {
        // 均等なら期待値の ±10% に収まる。偏った実装（定数返しや
        // 日付依存）ならこの範囲を外れる。
        expect(count, closeTo(expected, expected * 0.1));
      }
    });
  });
}
