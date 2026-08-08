// =============================================================================
// pitch_track.dart
// マイク入力から抽出したF0（基本周波数）系列の前処理。
//
// 入力は「フレームごとのF0（Hz）」で、無声フレーム・ピッチ検出の信頼度が低い
// フレームは null で表現する。ピッチ検出器（YIN等）そのものはこの層には含めず、
// 純粋な数値処理だけを持つ。こうすることでマイクを使わずにテストできる。
//
// この層の責務は2つ。
//   1. Hz → セミトーンへの変換（対数スケール化）
//   2. オクターブエラーの除去（メディアンフィルタ）
//
// どちらも省略できない。詳細は各関数のコメントを参照。
// =============================================================================

import 'dart:math' as math;

/// セミトーン変換の基準周波数（Hz）。
///
/// 絶対値そのものは後段の正規化で打ち消されるため、値自体に意味はない。
/// A1 = 55Hz を置いて、人の声域が正の値に収まるようにしている。
const double kSemitoneRefHz = 55.0;

/// メディアンフィルタの既定の窓幅（フレーム数）。奇数であること。
const int kMedianFilterWindow = 5;

/// F0（Hz）をセミトーンに変換する。
///
/// **Hzの線形値のまま扱ってはいけない。** 声の高さの知覚も、タイ語の声調が
/// 定義される尺度も対数スケールであり、線形のHzで差を取ると低い声の話者ほど
/// 変化量が小さく見積もられて判定が壊れる。
double? hzToSemitone(double? hz, {double refHz = kSemitoneRefHz}) {
  if (hz == null || hz <= 0) return null;
  return 12 * (math.log(hz / refHz) / math.ln2);
}

/// F0系列をまとめてセミトーンに変換する。
List<double?> toSemitones(
  List<double?> hz, {
  double refHz = kSemitoneRefHz,
}) =>
    hz.map((v) => hzToSemitone(v, refHz: refHz)).toList();

/// メディアンフィルタでオクターブエラーを除去する。
///
/// YIN系のピッチ検出器は、実際の1オクターブ上／下を誤って返すことがある
/// （倍音を基音と取り違える）。1フレームだけ12セミトーン跳ねるこの誤りを
/// 放置すると、**下降声が上昇声に化ける**。声調判定で最も多い故障モードなので
/// このフィルタは必須。
///
/// 中心が null（無声）のフレームは null のまま残す。無声区間は音節の切れ目の
/// 手がかりであり、埋めてはいけない。
List<double?> medianFilter(
  List<double?> values, {
  int window = kMedianFilterWindow,
}) {
  assert(window.isOdd, 'window は奇数であること');
  if (values.length < 2) return List<double?>.from(values);

  final half = window ~/ 2;
  final result = List<double?>.filled(values.length, null);

  for (var i = 0; i < values.length; i++) {
    if (values[i] == null) continue;

    final neighbors = <double>[];
    for (var j = math.max(0, i - half);
        j <= math.min(values.length - 1, i + half);
        j++) {
      final v = values[j];
      if (v != null) neighbors.add(v);
    }
    if (neighbors.isEmpty) continue;

    neighbors.sort();
    result[i] = neighbors[neighbors.length ~/ 2];
  }
  return result;
}

/// 有声（null でない）フレームの割合。
///
/// 騒音環境ではピッチが取れず、この値が落ちる。閾値を下回るときは採点せず
/// 「もう一度」を返すために使う。誤った採点結果を見せるより、採点を諦めるほうが
/// 機能への信頼を保てる。
double voicedRatio(List<double?> values) {
  if (values.isEmpty) return 0;
  final voiced = values.where((v) => v != null).length;
  return voiced / values.length;
}

/// F0（Hz）系列を、採点に使えるセミトーン系列へ整える。
///
/// 変換 → メディアンフィルタの順で適用する。フィルタはセミトーン領域で掛ける
/// （オクターブ誤りが「一定幅の跳ね」になり、対称に扱えるため）。
List<double?> preparePitchTrack(
  List<double?> hz, {
  double refHz = kSemitoneRefHz,
  int window = kMedianFilterWindow,
}) =>
    medianFilter(toSemitones(hz, refHz: refHz), window: window);
