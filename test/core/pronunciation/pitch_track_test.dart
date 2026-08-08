import 'package:flutter_test/flutter_test.dart';
import 'package:thai_memo/core/pronunciation/pitch_track.dart';

void main() {
  group('hzToSemitone', () {
    test('1オクターブ上は12セミトーン差になる', () {
      final low = hzToSemitone(110)!;
      final high = hzToSemitone(220)!;
      expect(high - low, closeTo(12, 1e-9));
    });

    test('無効な値は null', () {
      expect(hzToSemitone(null), isNull);
      expect(hzToSemitone(0), isNull);
      expect(hzToSemitone(-100), isNull);
    });

    test('低い声でも高い声でも同じ比なら同じ差になる', () {
      // 線形のHzで扱うと壊れる性質。対数化できているかの確認。
      final maleDelta = hzToSemitone(120)! - hzToSemitone(100)!;
      final femaleDelta = hzToSemitone(240)! - hzToSemitone(200)!;
      expect(maleDelta, closeTo(femaleDelta, 1e-9));
    });
  });

  group('medianFilter', () {
    test('1フレームだけのオクターブ誤りを除去する', () {
      // 平坦な系列の途中で1点だけ12セミトーン跳ねている。
      final values = <double?>[40, 40, 52, 40, 40, 40, 40];
      final filtered = medianFilter(values);
      expect(filtered[2], 40);
    });

    test('本当の変化は残す', () {
      // 下降声のような連続した動きは平滑化で消してはいけない。
      final values = <double?>[48, 47, 45, 42, 38, 35, 33];
      final filtered = medianFilter(values);
      expect(filtered.first! - filtered.last!, greaterThan(10));
    });

    test('無声フレームは埋めずに null のまま残す', () {
      final values = <double?>[40, 40, null, 40, 40];
      final filtered = medianFilter(values);
      expect(filtered[2], isNull);
    });

    test('要素が1つ以下でも落ちない', () {
      expect(medianFilter(<double?>[]), isEmpty);
      expect(medianFilter(<double?>[42]), [42]);
    });
  });

  group('voicedRatio', () {
    test('有声フレームの割合を返す', () {
      expect(voicedRatio(<double?>[1, null, 2, null]), 0.5);
      expect(voicedRatio(<double?>[]), 0);
      expect(voicedRatio(<double?>[null, null]), 0);
    });
  });

  group('preparePitchTrack', () {
    test('Hz からセミトーン系列を返し、長さを保つ', () {
      final track = preparePitchTrack(<double?>[110, 110, 220, 110, null]);
      expect(track.length, 5);
      expect(track.last, isNull);
      // 3点目のオクターブ誤りは除去されている。
      expect(track[2], closeTo(track[0]!, 1e-9));
    });
  });
}
