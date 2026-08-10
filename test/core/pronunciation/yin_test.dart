// 自前 YIN の検査。
//
// 使っていたライブラリは絶対閾値が 0.20 で固定され、下回る候補が無いと
// 確信度 0 を返した。実機で発話末の軋み声が全てそこに潰れ、拾えるのか本当に
// 周期が無いのかすら分からなくなっていた。ここでは**捨てずに確信度で返す**。
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:thai_memo/core/pronunciation/yin.dart';

const _sampleRate = 16000.0;
const _frame = 640; // 40ms

/// 正弦波のフレームを作る。
List<double> _sine(double hz, {double amplitude = 1.0, double noise = 0}) {
  final random = math.Random(7);
  return List<double>.generate(_frame, (i) {
    final phase = 2 * math.pi * hz * i / _sampleRate;
    final jitter = noise == 0 ? 0.0 : (random.nextDouble() * 2 - 1) * noise;
    return amplitude * math.sin(phase) + jitter;
  });
}

void main() {
  group('estimateF0', () {
    test('正弦波の周波数を当てる', () {
      for (final hz in [90.0, 150.0, 220.0, 330.0]) {
        final result = estimateF0(_sine(hz), _sampleRate);
        expect(result.f0Hz, isNotNull);
        expect(result.f0Hz!, closeTo(hz, hz * 0.03), reason: '$hz Hz');
        expect(result.pitched, isTrue);
        expect(result.confidence, greaterThan(0.8));
      }
    });

    test('振幅が小さくても周波数は変わらない', () {
      // 音量での足切りは別（gateByEnergy）。ここでは形だけを見る。
      final quiet = estimateF0(_sine(150, amplitude: 0.02), _sampleRate);
      expect(quiet.f0Hz!, closeTo(150, 5));
    });

    test('雑音が乗った周期は、確信度を下げつつ拾う', () {
      // **これが軋み声の扱い。** 閾値を切らなくても最良候補を返す。
      final noisy = estimateF0(_sine(120, noise: 0.9), _sampleRate);
      expect(noisy.f0Hz, isNotNull);
      expect(noisy.confidence, greaterThan(0.1));
      expect(noisy.confidence, lessThan(0.9));
    });

    test('閾値を切らなくても最良候補を返す', () {
      // 閾値を極端に厳しくすると pitched は落ちるが、候補と確信度は残る。
      final strict = estimateF0(_sine(150), _sampleRate, threshold: 0.0001);
      expect(strict.pitched, isFalse);
      expect(strict.f0Hz!, closeTo(150, 5));
      expect(strict.confidence, greaterThan(0.8));
    });

    test('確信度は周期のはっきりさに応じて下がる', () {
      final clean = estimateF0(_sine(150), _sampleRate).confidence;
      final noisy = estimateF0(_sine(150, noise: 0.5), _sampleRate).confidence;
      expect(noisy, lessThan(clean));
    });

    test('短すぎるフレームを受けても落ちない', () {
      expect(estimateF0(const [], _sampleRate).f0Hz, isNull);
      expect(estimateF0(const [0.1, 0.2], _sampleRate).f0Hz, isNull);
    });
  });

  group('frameRms', () {
    test('実効値を返す', () {
      expect(frameRms(const [1, -1, 1, -1]), closeTo(1.0, 1e-9));
      expect(frameRms(const [0, 0]), 0);
      expect(frameRms(const []), 0);
    });
  });
}
