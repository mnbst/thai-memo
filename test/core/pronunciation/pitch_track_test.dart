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

  group('speechSpan', () {
    test('声が続いているところを端にする', () {
      expect(speechSpan(<double?>[null, 1, 2, 3, null]), [1, 3]);
    });

    test('単発の有声フレームは端にしない', () {
      // 押した直後の物音を1フレーム拾うだけで、そこが発話の始まりになる。
      // 実機で、フレーム0だけ有声でその後 680ms 無音という録音が出て、
      // その間が丸ごと最初の音節に入った（有声2フレームで採点不能）。
      expect(
        speechSpan(<double?>[1, null, null, null, 5, 6, 7, null]),
        [4, 6],
      );
    });

    test('末尾の単発も端にしない', () {
      expect(
        speechSpan(<double?>[1, 2, 3, null, null, null, 9]),
        [0, 2],
      );
    });

    test('どこにも続きが無ければ null', () {
      expect(speechSpan(<double?>[1, null, 2, null]), isNull);
      expect(speechSpan(<double?>[]), isNull);
      expect(speechSpan(<double?>[null, null]), isNull);
    });
  });

  group('voicedRatio', () {
    test('声のある区間で割合を返す', () {
      expect(voicedRatio(<double?>[1, 2, 3, null, 4, 5, 6]), closeTo(6 / 7, 1e-9));
      expect(voicedRatio(<double?>[]), 0);
      expect(voicedRatio(<double?>[null, null]), 0);
    });

    test('前後の無音は分母に入れない', () {
      // 録音は押しっぱなしなので、押してから話し出すまでと、言い終わってから
      // 離すまでが必ず入る。全体で割ると**ゆっくり話した録音ほど弾かれる**。
      // 実機で 6.3秒の発話が 200/629 = 31.8% となり採点そのものが失敗した。
      const speech = <double?>[1, 2, 3, null, 4, 5, 6];
      const withSilence = <double?>[
        null, null, null, 1, 2, 3, null, 4, 5, 6, null, null,
      ];
      expect(voicedRatio(withSilence), voicedRatio(speech));
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

  group('gateByEnergy', () {
    test('音量の無いフレームは、ピッチが取れていても無声にする', () {
      // 押しはじめの無音。YINは暗騒音にもピッチを返すことがある。
      final gated = gateByEnergy(
        [120, 121, 200, 205, 210],
        [0.001, 0.001, 0.20, 0.22, 0.21],
      );
      expect(gated.sublist(0, 2), everyElement(isNull));
      expect(gated.sublist(2), everyElement(isNotNull));
    });

    test('弱く言われた音節は残す（発話の代表音量に対する比で見る）', () {
      final gated = gateByEnergy(
        [200, 200, 200],
        [0.30, 0.30 * 0.5, 0.30],
      );
      expect(gated, everyElement(isNotNull));
    });

    test('基準は最大値ではないので、単発の大きな音で発話が消えない', () {
      // 先頭のリップノイズが最大。基準を最大値に採ると以降が全て落ちる。
      final gated = gateByEnergy(
        List<double?>.filled(11, 200),
        [1.0, ...List<double>.filled(10, 0.10)],
      );
      expect(gated.sublist(1), everyElement(isNotNull));
    });

    test('もともと無声のフレームは無声のまま', () {
      final gated = gateByEnergy([null, 200], [0.30, 0.30]);
      expect(gated[0], isNull);
      expect(gated[1], isNotNull);
    });

    test('全て無音なら全て無声', () {
      expect(
        gateByEnergy([200, 200], [0, 0]),
        everyElement(isNull),
      );
    });

    test('空の入力を受けても落ちない', () {
      expect(gateByEnergy(const [], const []), isEmpty);
    });
  });
}
