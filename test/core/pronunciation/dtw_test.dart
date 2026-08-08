import 'package:flutter_test/flutter_test.dart';
import 'package:thai_memo/core/pronunciation/dtw.dart';

void main() {
  group('dtwAlign', () {
    test('同一の系列は対角線上で対応づく', () {
      final series = [0.0, 1.0, 2.0, 3.0];
      final path = dtwAlign(series, series);
      for (final point in path) {
        expect(point.refIndex, point.queryIndex);
      }
    });

    test('両端は必ず対応づく', () {
      final path = dtwAlign([0.0, 1.0, 2.0], [0.0, 0.5, 1.0, 1.5, 2.0]);
      expect(path.first.refIndex, 0);
      expect(path.first.queryIndex, 0);
      expect(path.last.refIndex, 2);
      expect(path.last.queryIndex, 4);
    });

    test('経路は単調に進む', () {
      final path = dtwAlign([0.0, 1.0, 2.0, 1.0], [0.0, 0.4, 1.2, 2.1, 1.1]);
      for (var i = 1; i < path.length; i++) {
        expect(path[i].refIndex, greaterThanOrEqualTo(path[i - 1].refIndex));
        expect(path[i].queryIndex, greaterThanOrEqualTo(path[i - 1].queryIndex));
      }
    });

    test('話速が違っても同じ形なら対応づく', () {
      // 同じ上昇カーブを2倍の長さで発話した場合。
      final reference = [0.0, 1.0, 2.0, 3.0];
      final slow = [0.0, 0.5, 1.0, 1.5, 2.0, 2.5, 3.0, 3.0];
      final path = dtwAlign(reference, slow);
      // お手本の全点が経路に現れる。
      final covered = path.map((p) => p.refIndex).toSet();
      expect(covered, {0, 1, 2, 3});
    });

    test('空の入力では空の経路', () {
      expect(dtwAlign([], [1.0]), isEmpty);
      expect(dtwAlign([1.0], []), isEmpty);
    });
  });
}
