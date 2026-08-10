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

/// 音節の真ん中で声の途切れに当たったときの費用。
///
/// 0 だと長い途切れの中で経路が自由に滑り、境界の位置が決まらない。大きくすると
/// 途切れを避けようとして、実際に子音のある位置から境界がずれる。
/// ピッチの差（0〜2程度）より十分小さく置く。合成音声で 120ms の無声子音を
/// 各音節の頭に入れた条件で、0.15 以上にすると音節の取り分が歪んだ。
const double kVoicelessDriftCost = 0.1;

/// **切れ目に負の費用を置いてはいけない（測って不採用）。** DTW は経路の総和を
/// 最小化するので、負の点があるとそこに居座るほど得になり、値の大小によらず
/// 同じ退化した経路になる（0.05 と 0.3 で結果が完全に一致した）。
/// 引き寄せたいなら費用ではなく**通れる範囲の制約**で表す（[boundaryWindows]）。

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
  List<bool>? queryVoiced,
  List<bool>? referenceAtBoundary,
  Map<int, List<int>>? boundaryWindows,
  List<double>? referenceToQuery,
}) {
  if (reference.isEmpty || query.isEmpty) return const [];

  final n = reference.length;
  final m = query.length;

  /// **音節の切れ目は、声が途切れているところに置く。** お手本の切れ目に当たる
  /// 点について「録音側のこの範囲を通れ」と指定できる。費用で引き寄せると経路が
  /// そこに居座るので、通れる範囲そのものを絞る。
  ///
  /// 指定の無い点は帯だけで制限する（従来どおり）。
  bool inWindow(int i, int j) {
    final window = boundaryWindows?[i];
    if (window == null) return true;
    return j >= window[0] && j <= window[1];
  }

  /// お手本の点 [i] が録音側のどこに来るはずか。
  ///
  /// 既定は対角線（時間が比例している前提）。[referenceToQuery] を渡すと、
  /// **声の途切れで分かった音節の切れ目を通る折れ線**に置き換わる。
  /// 予算（表記から決めた時間配分）の誤差が文全体に積み上がって帯を食い潰す
  /// のを防げる。誤差は切れ目ごとにリセットされる。
  double expected(int i) {
    final map = referenceToQuery;
    if (map != null && i < map.length) return map[i];
    return n == 1 ? 0 : i / (n - 1) * (m - 1);
  }

  /// (i, j) が帯の中にあるか。
  ///
  /// 帯の幅は録音の長さに対する割合なので、系列の長さが違っても同じ意味になる。
  bool inBand(int i, int j) {
    if (n == 1 || m == 1) return true;
    return (j - expected(i)).abs() <= bandRatio * (m - 1);
  }

  bool allowed(int i, int j) => inBand(i, j) && inWindow(i, j);

  // cost[i][j] = reference[0..i] と query[0..j] を対応づけた累積コスト。
  final cost = List.generate(
    n,
    (_) => List<double>.filled(m, double.infinity),
    growable: false,
  );

  // **声が出ていないフレームは、時間は占めるがピッチの証拠を持たない。**
  // 閉鎖音の閉鎖区間を埋めた値は前後の線形補間でしかないので、これをお手本と
  // 突き合わせると、実在しないピッチで経路が引っ張られる。時間軸を保つために
  // フレームは残したまま、コストだけ 0 にして「どこに対応してもよい」とする。
  bool voiced(int j) =>
      queryVoiced == null || j >= queryVoiced.length || queryVoiced[j];

  /// お手本のこの点が、音節の端（入り際・終わり際）にあるか。
  bool atBoundary(int i) =>
      referenceAtBoundary == null ||
      i >= referenceAtBoundary.length ||
      referenceAtBoundary[i];

  double distance(int i, int j) {
    if (voiced(j)) return (reference[i] - query[j]).abs();
    // **声の途切れは音節の切れ目の手がかり。** コストを一律 0 にすると、長い
    // 途切れの中では経路がどこを通っても同じになり、境界の位置が決まらない。
    // 実機で 440ms の空白が音節の真ん中に飲み込まれ、隣が9フレームまで潰れた。
    //
    // 音節の端で途切れに当たるのはただ（子音はそこにある）。真ん中で当たるのは
    // わずかに損にする。これだけで、長い途切れは音節の切れ目へ寄る。
    return atBoundary(i) ? 0.0 : kVoicelessDriftCost;
  }

  cost[0][0] = distance(0, 0);
  for (var i = 1; i < n; i++) {
    if (!allowed(i, 0)) break;
    cost[i][0] = cost[i - 1][0] + distance(i, 0);
  }
  for (var j = 1; j < m; j++) {
    if (!allowed(0, j)) break;
    cost[0][j] = cost[0][j - 1] + distance(0, j);
  }
  for (var i = 1; i < n; i++) {
    for (var j = 1; j < m; j++) {
      if (!allowed(i, j)) continue;
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
