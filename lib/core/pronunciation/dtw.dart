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

/// 2つの系列を対応づけ、経路を先頭から順に返す。
///
/// ステップは (1,0) / (0,1) / (1,1) の3方向。両端は必ず対応づく
/// （発話の頭とお尻がお手本の頭とお尻に対応する）。
///
/// どちらかが空なら空の経路を返す。
List<DtwPathPoint> dtwAlign(List<double> reference, List<double> query) {
  if (reference.isEmpty || query.isEmpty) return const [];

  final n = reference.length;
  final m = query.length;

  // cost[i][j] = reference[0..i] と query[0..j] を対応づけた累積コスト。
  final cost = List.generate(
    n,
    (_) => List<double>.filled(m, double.infinity),
    growable: false,
  );

  double distance(int i, int j) => (reference[i] - query[j]).abs();

  cost[0][0] = distance(0, 0);
  for (var i = 1; i < n; i++) {
    cost[i][0] = cost[i - 1][0] + distance(i, 0);
  }
  for (var j = 1; j < m; j++) {
    cost[0][j] = cost[0][j - 1] + distance(0, j);
  }
  for (var i = 1; i < n; i++) {
    for (var j = 1; j < m; j++) {
      final best = math.min(
        cost[i - 1][j - 1],
        math.min(cost[i - 1][j], cost[i][j - 1]),
      );
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
      if (diagonal <= up && diagonal <= left) {
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
