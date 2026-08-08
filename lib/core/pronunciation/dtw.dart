// =============================================================================
// dtw.dart
// DTW（動的時間伸縮）によるお手本カーブと録音ピッチの対応づけ。
//
// 「録音のどこが何番目の音節か」を決めるための仕組み。タイ語は音節の切れ目で
// 有声が途切れにくく、無音による区切りが当てにならない。区間検出のヒューリスティック
// （等分割・エネルギー谷）を積むより、カーブ同士を直接対応づけるほうが堅く、
// 話速のばらつきもそのまま吸収できる。
//
// 計算量は O(ref × query)。音節30 → ref 300点、5秒／ホップ10ms → query 500点で
// 15万セル程度なので、端末上で問題にならない。
//
// **経路には帯（Sakoe-Chiba band）を必ず掛ける。** 制限しないDTWは全体の距離を
// 最小化しようとして経路を大きく歪め、誤った音節に隣からフレームを盗んで
// 誤りを隠してしまう。実測では、上昇声で発音した音節が13フレームしか
// 割り当てられず、しかも傾きが -1.51（下降）と測れていた。
// 発音の誤りが検出できなくなるうえ、正しい発話も不安定に採点される。
// =============================================================================

import 'dart:math' as math;

/// 対応づけの1点。
class DtwPathPoint {
  /// お手本カーブ側の添字。
  final int refIndex;

  /// 録音側の添字。
  final int queryIndex;

  const DtwPathPoint(this.refIndex, this.queryIndex);

  @override
  String toString() => '($refIndex, $queryIndex)';
}

/// 経路が対角線から離れてよい幅（両系列の長さに対する割合）。
///
/// タイ語の音節はおおむね等時的なので、対応づけは対角線の近くにあるはず。
/// 広げるほど話速のばらつきを吸収できるが、広げすぎると誤った音節が
/// 隣からフレームを借りて誤りを隠す。
///
/// 実測では 0.10 でも足りず、**上昇声で発音した音節の傾きが -0.81（下降）と
/// 測れていた**。隣の下降部分を借りていたため。0.06 まで締めると測った向きが
/// 実際の発音と一致するようになる。締めすぎると話速のばらつきを吸収できないので、
/// 無声子音を含む条件でも正しい発話が通ることを確認したうえでこの値にしている。
const double kDtwBandRatio = 0.06;

/// 2つの系列を対応づけ、経路を先頭から順に返す。
///
/// ステップは (1,0) / (0,1) / (1,1) の3方向。両端は必ず対応づく
/// （発話の頭とお尻がお手本の頭とお尻に対応する）。
///
/// [bandRatio] は経路が対角線から離れてよい幅。
///
/// どちらかが空なら空の経路を返す。
List<DtwPathPoint> dtwAlign(
  List<double> reference,
  List<double> query, {
  double bandRatio = kDtwBandRatio,
}) {
  if (reference.isEmpty || query.isEmpty) return const [];

  final n = reference.length;
  final m = query.length;

  /// (i, j) が帯の中にあるか。
  ///
  /// 正規化した位置の差で見るので、系列の長さが違っても同じ意味になる。
  bool inBand(int i, int j) {
    if (n == 1 || m == 1) return true;
    final di = i / (n - 1);
    final dj = j / (m - 1);
    return (di - dj).abs() <= bandRatio;
  }

  // cost[i][j] = reference[0..i] と query[0..j] を対応づけた累積コスト。
  final cost = List.generate(
    n,
    (_) => List<double>.filled(m, double.infinity),
    growable: false,
  );

  double distance(int i, int j) => (reference[i] - query[j]).abs();

  cost[0][0] = distance(0, 0);
  for (var i = 1; i < n; i++) {
    if (!inBand(i, 0)) break;
    cost[i][0] = cost[i - 1][0] + distance(i, 0);
  }
  for (var j = 1; j < m; j++) {
    if (!inBand(0, j)) break;
    cost[0][j] = cost[0][j - 1] + distance(0, j);
  }
  for (var i = 1; i < n; i++) {
    for (var j = 1; j < m; j++) {
      if (!inBand(i, j)) continue;
      final best = math.min(
        cost[i - 1][j - 1],
        math.min(cost[i - 1][j], cost[i][j - 1]),
      );
      if (best.isInfinite) continue;
      cost[i][j] = distance(i, j) + best;
    }
  }

  // 終端から逆にたどる。
  final path = <DtwPathPoint>[];
  var i = n - 1;
  var j = m - 1;
  path.add(DtwPathPoint(i, j));
  while (i > 0 || j > 0) {
    if (i == 0) {
      j--;
    } else if (j == 0) {
      i--;
    } else {
      final diagonal = cost[i - 1][j - 1];
      final up = cost[i - 1][j];
      final left = cost[i][j - 1];
      if (diagonal.isInfinite && up.isInfinite && left.isInfinite) {
        // 帯の外に出た。両端は必ず対応づけるので、斜めに戻す。
        i--;
        j--;
      } else if (diagonal <= up && diagonal <= left) {
        i--;
        j--;
      } else if (up <= left) {
        i--;
      } else {
        j--;
      }
    }
    path.add(DtwPathPoint(i, j));
  }

  return path.reversed.toList();
}
