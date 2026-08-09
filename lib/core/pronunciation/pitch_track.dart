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

/// 有声と認めるフレームの音量の下限（発話の代表的な音量に対する比）。
///
/// 0.06 はおよそ -24dB。文中で弱く言われた音節でもここまでは落ちない一方、
/// 発話前後の暗騒音はこれを下回る。
const double kMinFrameEnergyRatio = 0.06;

/// 発話の代表音量を採るパーセンタイル。
///
/// 最大値だと、リップノイズやボタンを押した音ひとつで基準が跳ね上がり、
/// 発話そのものが無音扱いになる。
const double kEnergyReferencePercentile = 0.9;

/// 音量の足りないフレームを無声として落とす。
///
/// **ピッチが取れたことは、声が出ていたことを意味しない。** YIN は暗騒音や
/// 空調のハムのような弱い周期性にも高い信頼度を返すことがあり、そのままだと
/// 押しはじめの無音が「発声した区間」として取り込まれる。前後の無音は
/// [analyzePronunciation] が切り落とすが、それは無声フレームに限るので、
/// ここで落としておかないと残る。
///
/// 害は先頭が汚れることに留まらない。DTW はその区間も音節に割り当てなければ
/// ならず、**お手本の先頭の音節が無音とつき合わされて、以降の対応づけが丸ごと
/// ずれる**。
///
/// 閾値は絶対値では置けない（マイクの利得も声量も端末と場面で変わる）ので、
/// その録音自身の代表音量に対する比で決める。
List<double?> gateByEnergy(
  List<double?> f0,
  List<double> rms, {
  double ratio = kMinFrameEnergyRatio,
}) {
  assert(f0.length == rms.length, 'F0とRMSはフレーム数を揃えること');
  if (f0.isEmpty) return const [];

  final levels = rms.where((v) => v > 0).toList()..sort();
  if (levels.isEmpty) return List<double?>.filled(f0.length, null);

  final index = (levels.length * kEnergyReferencePercentile)
      .floor()
      .clamp(0, levels.length - 1);
  final floor = levels[index] * ratio;

  return [
    for (var i = 0; i < f0.length; i++)
      i < rms.length && rms[i] >= floor ? f0[i] : null,
  ];
}

/// 補間してよい無声区間の最大長（フレーム数）。ホップ10msで120ms。
///
/// 子音1つぶんの無声区間はこの程度に収まる。これを超える空白は語間の間なので、
/// 埋めずに残す。
const int kMaxInterpolatedGap = 12;

/// 短い無声区間をまたいでF0を線形補間する。
///
/// **無声フレームを捨ててはいけない。** 子音（破裂音・摩擦音）の無声区間を
/// 落とすと時間軸が縮むうえ、縮み方が音節ごとに違う。DTWの帯は「時間が比例して
/// いる」ことを前提にしているので、この歪みを吸収できず、対応づけがずれる。
/// カーブも有声区間の継ぎ目で垂直に跳んで見える。
///
/// 前後を有声に挟まれた短い空白だけを埋める。発話の前後の無音や、語間の長い間は
/// 埋めない（そこは実際に声が無い）。
List<double?> interpolateShortGaps(
  List<double?> values, {
  int maxGap = kMaxInterpolatedGap,
}) {
  final result = List<double?>.from(values);

  var i = 0;
  while (i < result.length) {
    if (result[i] != null) {
      i++;
      continue;
    }

    final gapStart = i;
    while (i < result.length && result[i] == null) {
      i++;
    }
    final gapEnd = i; // 空白の次の有声フレーム

    // 前後を有声に挟まれていて、かつ十分短いときだけ埋める。
    if (gapStart == 0 || gapEnd >= result.length) continue;
    if (gapEnd - gapStart > maxGap) continue;

    final before = result[gapStart - 1]!;
    final after = result[gapEnd]!;
    final steps = gapEnd - gapStart + 1;
    for (var k = gapStart; k < gapEnd; k++) {
      final ratio = (k - gapStart + 1) / steps;
      result[k] = before + (after - before) * ratio;
    }
  }

  return result;
}

/// 発話全体にかかる直線的な傾きを取り除く。
///
/// 実際の発話は文が進むにつれてピッチが下がる（declination）。話者が意図して
/// やっているわけではないので、これを声調の誤りとして数えてはいけない。
/// 取り除かないと、**文末に近い音節ほど不当に低いと判定される**。
/// 文末の丁寧語尾（ครับ / ค่ะ）は毎回その位置に来るため、影響が常に同じ語へ集中する。
///
/// 平均は動かさない（傾きだけを抜く）。後段の正規化が平均を落とすので、
/// ここで水準まで動かす必要はない。
List<double?> detrendSemitones(List<double?> values) {
  final indices = <int>[];
  final voiced = <double>[];
  for (var i = 0; i < values.length; i++) {
    final v = values[i];
    if (v != null) {
      indices.add(i);
      voiced.add(v);
    }
  }
  if (voiced.length < 2) return List<double?>.from(values);

  final meanIndex = indices.reduce((a, b) => a + b) / indices.length;
  final meanValue = voiced.reduce((a, b) => a + b) / voiced.length;

  var covariance = 0.0;
  var variance = 0.0;
  for (var k = 0; k < voiced.length; k++) {
    final di = indices[k] - meanIndex;
    covariance += di * (voiced[k] - meanValue);
    variance += di * di;
  }
  if (variance.abs() < 1e-9) return List<double?>.from(values);

  final slope = covariance / variance;
  return List<double?>.generate(values.length, (i) {
    final v = values[i];
    return v == null ? null : v - slope * (i - meanIndex);
  });
}

/// F0（Hz）系列を、採点に使えるセミトーン系列へ整える。
///
/// 変換 → メディアンフィルタ → 短い無声区間の補間、の順で適用する。
/// フィルタはセミトーン領域で掛ける（オクターブ誤りが「一定幅の跳ね」になり、
/// 対称に扱えるため）。
///
/// 傾き除去（[detrendSemitones]）はここでは掛けない。6音節程度の文では、
/// 推定した傾きが**先頭・末尾の音節の声調そのものを吸収**してしまい、
/// 中平声と低平声の取り違えが検出できなくなる（実測でレベル誤差 0.562 → 0.051）。
/// declination はお手本側に位置依存の傾きとして持たせる。
List<double?> preparePitchTrack(
  List<double?> hz, {
  double refHz = kSemitoneRefHz,
  int window = kMedianFilterWindow,
}) =>
    interpolateShortGaps(
      medianFilter(toSemitones(hz, refHz: refHz), window: window),
    );
