// =============================================================================
// yin.dart
// YIN によるフレーム単位のF0推定。
//
// **`pitch_detector_dart` を使わず自前で持つ理由。** あちらは YIN の絶対閾値が
// 0.20 で固定されており（`yin.dart` の `defaultThreshold`）、そこを下回る候補が
// 無いと「ピッチ無し・確信度0」を返す。実機で、発話末の軋み声（creaky voice）が
// この扱いになり、**落としたフレームの確信度が全て 0.1 未満に潰れていた**
// （6.3秒の発話で 629 フレーム中 429 が無声判定）。閾値も触れず、確信度が階調で
// 出ないので、「拾えるのに捨てているのか、本当に周期が無いのか」すら分からない。
//
// ここでは
//   - 閾値を呼び出し側から渡せるようにする
//   - 閾値を下回る候補が無くても、**最良候補を確信度つきで返す**
// の2点だけを変える。アルゴリズムそのものは YIN の論文どおり。
//
// 判定に使うかどうかは呼び出し側が確信度で決める。ここでは捨てない。
// =============================================================================

import 'dart:math' as math;

/// YIN の絶対閾値。
///
/// 論文の推奨は 0.10〜0.15、TarsosDSP は 0.20。**この値は「ここまでなら周期と
/// 認めてよい」の線**で、下回る候補が無ければ最良候補に落ちる（捨てない）。
const double kYinThreshold = 0.20;

/// 最も深い谷とどこまで同じ深さなら「同じ周期」とみなすか。
///
/// d' は周期の整数倍でも谷になる。純音では2倍周期のほうが深くなることがあり、
/// 最小値をそのまま採ると**1オクターブ下に落ちる**。ほぼ同じ深さなら早いほうを
/// 採る（基本周期は最も早い谷）。
const double kOctaveTolerance = 0.1;

/// 1フレームの推定結果。
class YinResult {
  /// 推定した基本周波数（Hz）。候補が全く取れなければ null。
  final double? f0Hz;

  /// 確信度（0〜1）。1 に近いほど周期がはっきりしている。
  ///
  /// **閾値を下回らなかったフレームでも階調で返す。** 軋み声は 0.3〜0.6 あたりに
  /// 出るので、ここを潰すと発話末が丸ごと測れなくなる。
  final double confidence;

  /// 絶対閾値を下回る候補が見つかったか（YIN 本来の有声判定）。
  final bool pitched;

  const YinResult({
    required this.f0Hz,
    required this.confidence,
    required this.pitched,
  });

  static const none =
      YinResult(f0Hz: null, confidence: 0, pitched: false);
}

/// フレーム [samples]（-1..1 に正規化した波形）から F0 を推定する。
///
/// [sampleRate] は Hz。[threshold] は [kYinThreshold] を参照。
YinResult estimateF0(
  List<double> samples,
  double sampleRate, {
  double threshold = kYinThreshold,
}) {
  final half = samples.length ~/ 2;
  if (half < 2) return YinResult.none;

  // 1. 差分関数 d(tau)
  final difference = List<double>.filled(half, 0);
  for (var tau = 1; tau < half; tau++) {
    var sum = 0.0;
    for (var i = 0; i < half; i++) {
      final delta = samples[i] - samples[i + tau];
      sum += delta * delta;
    }
    difference[tau] = sum;
  }

  // 2. 累積平均で正規化した差分 d'(tau)
  final normalized = List<double>.filled(half, 1);
  var runningSum = 0.0;
  for (var tau = 1; tau < half; tau++) {
    runningSum += difference[tau];
    normalized[tau] =
        runningSum == 0 ? 1 : difference[tau] * tau / runningSum;
  }

  // 3. 絶対閾値。**下回る候補が無くても諦めない。**
  var tau = -1;
  for (var t = 2; t < half; t++) {
    if (normalized[t] >= threshold) continue;
    // 谷の底まで降りる（最初に閾値を切った点は底ではない）。
    while (t + 1 < half && normalized[t + 1] < normalized[t]) {
      t++;
    }
    tau = t;
    break;
  }
  final pitched = tau != -1;
  if (!pitched) {
    // 最良候補を採る。**単純な最小値を採ってはいけない。** d' は周期の整数倍でも
    // 谷になるので、純音では2倍周期（1オクターブ下）のほうが深くなることがある。
    // 谷を全部拾い、最も深い谷とほぼ同じ深さのものの**いちばん早いもの**を選ぶ。
    var deepest = double.infinity;
    for (var t = 2; t < half - 1; t++) {
      if (normalized[t] <= normalized[t - 1] &&
          normalized[t] <= normalized[t + 1] &&
          normalized[t] < deepest) {
        deepest = normalized[t];
      }
    }
    if (deepest.isInfinite) return YinResult.none;
    final limit = deepest + kOctaveTolerance;
    for (var t = 2; t < half - 1; t++) {
      if (normalized[t] <= normalized[t - 1] &&
          normalized[t] <= normalized[t + 1] &&
          normalized[t] <= limit) {
        tau = t;
        break;
      }
    }
    if (tau < 0) return YinResult.none;
  }
  if (tau <= 0 || tau >= half) return YinResult.none;

  // 4. 放物線補間で tau を細かく取る。
  final refined = _refine(normalized, tau, half);
  if (refined <= 0) return YinResult.none;

  return YinResult(
    f0Hz: sampleRate / refined,
    // d' は 0 で完全な周期、1 で無関係。確信度に読み替える。
    confidence: (1 - normalized[tau]).clamp(0.0, 1.0),
    pitched: pitched,
  );
}

/// 谷の位置を放物線で補間する。
double _refine(List<double> normalized, int tau, int half) {
  final previous = tau > 0 ? tau - 1 : tau;
  final next = tau + 1 < half ? tau + 1 : tau;
  if (previous == tau) {
    return normalized[tau] <= normalized[next] ? tau.toDouble() : next.toDouble();
  }
  if (next == tau) {
    return normalized[tau] <= normalized[previous]
        ? tau.toDouble()
        : previous.toDouble();
  }
  final a = normalized[previous];
  final b = normalized[tau];
  final c = normalized[next];
  final denominator = 2 * (2 * b - c - a);
  if (denominator.abs() < 1e-12) return tau.toDouble();
  return tau + (c - a) / denominator;
}

/// 波形の実効値（RMS）。
double frameRms(List<double> window) {
  if (window.isEmpty) return 0;
  var sum = 0.0;
  for (final value in window) {
    sum += value * value;
  }
  return math.sqrt(sum / window.length);
}
