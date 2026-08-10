// 声の途切れを音節の切れ目に割り当てる部分の検査。
//
// タイ語の音節は必ず子音で始まり、閉鎖音・摩擦音なら声が止まる。だから途切れは
// 音節の切れ目の**部分集合**になる。共鳴音で繋がる境界（งาน→นะ、บรร→ยา）には
// 出ないので、数を合わせてはいけない。
import 'package:flutter_test/flutter_test.dart';
import 'package:thai_memo/core/pronunciation/pronunciation_analyzer.dart';
import 'package:thai_memo/core/pronunciation/tone_contour.dart';
import 'package:thai_memo/core/thai_tone_analyzer.dart';

const _tones = [
  ThaiTone.mid,
  ThaiTone.falling,
  ThaiTone.low,
  ThaiTone.rising,
];

ReferenceContour _reference() => ReferenceContour.fromTones(_tones);

void main() {
  group('assignGapsToSeams', () {
    // 音節4つ・お手本40点。録音400フレームなら切れ目の予想位置は 100/200/300。
    test('予想位置の近くの途切れを割り当てる', () {
      final reference = _reference();
      final anchors = assignGapsToSeams(
        reference: reference,
        voicelessGaps: [
          [98, 104],
          [301, 308],
        ],
        queryLength: 400,
      );
      expect(anchors[reference.starts[1]], [98, 104]);
      expect(anchors[reference.starts[3]], [301, 308]);
      // 繋がっている境界には途切れが出ない。付かないまま残る。
      expect(anchors.containsKey(reference.starts[2]), isFalse);
    });

    test('順序は追い越さない', () {
      final reference = _reference();
      final anchors = assignGapsToSeams(
        reference: reference,
        voicelessGaps: [
          [95, 100],
          [195, 200],
          [295, 300],
        ],
        queryLength: 400,
      );
      expect(anchors[reference.starts[1]], [95, 100]);
      expect(anchors[reference.starts[2]], [195, 200]);
      expect(anchors[reference.starts[3]], [295, 300]);
    });

    test('遠すぎる途切れは捨てる（母音の途中で声が落ちることがある）', () {
      final reference = _reference();
      final anchors = assignGapsToSeams(
        reference: reference,
        // 予想位置 100 から 100 フレーム（25%）離れている。
        voicelessGaps: [
          [198, 202],
        ],
        queryLength: 400,
      );
      // 切れ目2（予想 200）のほうへ付く。切れ目1には付かない。
      expect(anchors[reference.starts[2]], [198, 202]);
      expect(anchors.containsKey(reference.starts[1]), isFalse);
    });

    test('帯より広く探す', () {
      // 予算の誤差が帯（6%）を超えても、割り当ては成立させる。
      // この割り当てが帯そのものを引き直すので、帯の内側にある必要はない。
      final reference = _reference();
      final anchors = assignGapsToSeams(
        reference: reference,
        voicelessGaps: [
          [138, 144],
        ],
        queryLength: 400,
      );
      expect(anchors[reference.starts[1]], [138, 144]);
    });

    test('予想位置を含む途切れを選ぶ（中心までの距離で測らない）', () {
      // 長い途切れは位置の幅を持っている。中心で測ると、短い途切れのほうが
      // 「近い」ことになる。実機で、`ให้` の直後の 770ms の間（予想位置はその中）
      // ではなく手前の3フレームの途切れが錨に選ばれ、間より後ろの音節が
      // 丸ごと1つずれた（点数 62.5、9音節中5個が採点不能）。
      // 切れ目1つだけの文で見る（複数あると全体最適が絡む）。
      final reference = ReferenceContour.fromTones(
        const [ThaiTone.mid, ThaiTone.high],
      );
      final anchors = assignGapsToSeams(
        reference: reference,
        // お手本20点・録音400フレームなら切れ目の予想位置は 200。
        voicelessGaps: [
          // 中心（193）は近いが、区間は予想位置に届いていない。
          [190, 196],
          // 中心（240）は遠いが、区間が予想位置 200 を含む。
          [199, 280],
        ],
        queryLength: 400,
      );
      expect(anchors[reference.starts[1]], [199, 280]);
    });

    test('区間から遠ければ、長くても使わない', () {
      final reference = _reference();
      final anchors = assignGapsToSeams(
        reference: reference,
        // 予想位置 100 から区間の端まで 80 フレーム（20%）。
        voicelessGaps: [
          [180, 260],
        ],
        queryLength: 400,
      );
      expect(anchors.containsKey(reference.starts[1]), isFalse);
    });

    test('途切れが無ければ何も決めない', () {
      expect(
        assignGapsToSeams(
          reference: _reference(),
          voicelessGaps: const [],
          queryLength: 400,
        ),
        isEmpty,
      );
    });
  });

  group('referenceToQueryFrom', () {
    test('錨が無ければ対角線', () {
      final map = referenceToQueryFrom(
        referenceLength: 5,
        queryLength: 9,
        anchors: const {},
      );
      expect(map, [0, 2, 4, 6, 8]);
    });

    test('錨を通る折れ線になる', () {
      // お手本の点2を録音の6に固定すると、前半は急に、後半は緩やかになる。
      final map = referenceToQueryFrom(
        referenceLength: 5,
        queryLength: 9,
        anchors: const {
          2: [5, 7],
        },
      );
      expect(map[0], 0);
      expect(map[2], 6);
      expect(map[4], 8);
      expect(map[1], 3);
      expect(map[3], 7);
    });
  });
}
