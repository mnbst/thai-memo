// 音量の谷から音節の切れ目を拾う部分の検査。
//
// 共鳴音で繋がる切れ目（ชิ้น น → นี้ น）は F0 にも無声区間にも現れない。
// 鼻音・側音は母音より弱いので、そこは音量が凹む。分割の唯一の手がかりになる。
import 'package:flutter_test/flutter_test.dart';
import 'package:thai_memo/core/pronunciation/pronunciation_analyzer.dart';
import 'package:thai_memo/core/pronunciation/tone_contour.dart';
import 'package:thai_memo/core/thai_tone_analyzer.dart';

/// 山と谷を並べた音量の列を作る。
List<double> _contour(List<double> levels, {int framesEach = 8}) => [
      for (final level in levels)
        for (var i = 0; i < framesEach; i++) level,
    ];

void main() {
  group('findEnergyValleys', () {
    test('母音のあいだの深い谷を拾う', () {
      // 母音(1.0) → 鼻音(0.3) → 母音(1.0)
      final valleys = findEnergyValleys(_contour([1.0, 0.3, 1.0]));
      expect(valleys, isNotEmpty);
      final center = valleys.first[0];
      expect(center, greaterThanOrEqualTo(8));
      expect(center, lessThan(16));
    });

    test('浅い揺れは拾わない', () {
      // 母音の中の微細な変動を切れ目にしてはいけない。
      expect(findEnergyValleys(_contour([1.0, 0.8, 1.0])), isEmpty);
    });

    test('谷が2つあれば2つとも拾う', () {
      final valleys = findEnergyValleys(
        _contour([1.0, 0.2, 1.0, 0.2, 1.0]),
      );
      expect(valleys.length, 2);
    });

    test('近すぎる谷は1つとして扱う', () {
      // 音節は 60ms より短くならない。
      final valleys = findEnergyValleys([
        1.0, 1.0, 0.2, 1.0, 0.2, 1.0, 1.0,
      ]);
      expect(valleys.length, 1);
    });

    test('単調に下がるだけの箇所は谷ではない', () {
      expect(findEnergyValleys(_contour([1.0, 0.6, 0.3])), isEmpty);
    });

    test('短すぎる入力を受けても落ちない', () {
      expect(findEnergyValleys(const []), isEmpty);
      expect(findEnergyValleys(const [1.0, 0.2]), isEmpty);
    });
  });

  group('fillSeamsWithValleys', () {
    // 谷は途切れと同格に扱わない。途切れで決まらなかった切れ目にだけ使う。
    final reference = ReferenceContour.fromTones(const [
      ThaiTone.mid,
      ThaiTone.high,
      ThaiTone.high,
      ThaiTone.low,
    ]);
    // お手本40点・録音400フレームなら、切れ目の予想位置は 100 / 200 / 300。
    List<double> lineFor(Map<int, List<int>> anchors) => referenceToQueryFrom(
          referenceLength: reference.values.length,
          queryLength: 400,
          anchors: anchors,
        );

    test('途切れが付いた切れ目には触らない', () {
      final anchors = {
        reference.starts[1]: [95, 100],
      };
      final filled = fillSeamsWithValleys(
        reference: reference,
        anchors: anchors,
        valleys: [
          [98, 98],
        ],
        referenceToQuery: lineFor(anchors),
        queryLength: 400,
      );
      expect(filled[reference.starts[1]], [95, 100]);
    });

    test('空いている切れ目を谷で埋める', () {
      final filled = fillSeamsWithValleys(
        reference: reference,
        anchors: const {},
        valleys: [
          [203, 203],
        ],
        referenceToQuery: lineFor(const {}),
        queryLength: 400,
      );
      expect(filled[reference.starts[2]], [203, 203]);
    });

    test('遠い谷は使わない（証拠として弱い）', () {
      final filled = fillSeamsWithValleys(
        reference: reference,
        anchors: const {},
        // 予想位置 200 から 40 フレーム（10%）離れている。
        valleys: [
          [240, 240],
        ],
        referenceToQuery: lineFor(const {}),
        queryLength: 400,
      );
      expect(filled, isEmpty);
    });

    test('隣の錨を越える谷は使わない（音節が入れ替わる）', () {
      final anchors = {
        reference.starts[3]: [205, 210],
      };
      final filled = fillSeamsWithValleys(
        reference: reference,
        anchors: anchors,
        // 切れ目2（予想位置は折れ線の上）の候補だが、切れ目3の錨より後ろにある。
        valleys: [
          [230, 230],
        ],
        referenceToQuery: lineFor(anchors),
        queryLength: 400,
      );
      expect(filled.containsKey(reference.starts[2]), isFalse);
    });
  });
}
