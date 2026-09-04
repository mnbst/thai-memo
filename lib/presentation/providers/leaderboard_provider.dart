import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'remaining_quota_provider.dart';
import 'vocab_stats_provider.dart';

/// 自分の上下に何人ぶん見せるか
const int leaderboardNeighborCount = 1;

/// 常に見せる上位の人数
const int leaderboardTopCount = 3;

/// 端末に置いた取得結果を再利用する時間。
///
/// 順位は他人の生成でしか動かないので、開くたび・起動するたびに数え直す必要がない。
/// この間はアプリを再起動しても Firestore を読まない（引っ張って更新は常に即取得）。
const Duration leaderboardCacheTtl = Duration(hours: 6);

// 帯の中の順位に変えたので鍵を変える。前の鍵のままだと、更新直後の6時間は
// 端末に残った全体順位がそのまま出てしまう。
const _rowsCacheKey = 'leaderboard_rows_cache_band';
const _distributionCacheKey = 'leaderboard_distribution_cache_band';
const _myRankCacheKey = 'leaderboard_my_rank_cache_band';

/// 引っ張って更新の回数。1以上なら、その起動中はキャッシュを使わない。
///
/// 増やすと leaderboard 系の provider が作り直され、そのまま再取得になる。
final leaderboardRefreshEpochProvider = StateProvider<int>((ref) => 0);

/// キャッシュの中身。uid と自分のスコアが一致し、TTL 内のときだけ返す。
///
/// 自分のスコアが変わると順位も周辺も変わるので、キャッシュの鍵に含める。
Future<Object?> _readCache(String key, String uid, int vocab) async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(key);
  if (raw == null) return null;

  final Map<String, dynamic> json;
  try {
    json = jsonDecode(raw) as Map<String, dynamic>;
  } catch (_) {
    return null;
  }
  if (json['uid'] != uid || json['vocab'] != vocab) return null;

  final at = (json['at'] as num?)?.toInt() ?? 0;
  final age = DateTime.now().millisecondsSinceEpoch - at;
  if (age < 0 || age > leaderboardCacheTtl.inMilliseconds) return null;
  return json['data'];
}

Future<void> _writeCache(
  String key,
  String uid,
  int vocab,
  Object? data,
) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(
    key,
    jsonEncode({
      'uid': uid,
      'vocab': vocab,
      'at': DateTime.now().millisecondsSinceEpoch,
      'data': data,
    }),
  );
}

/// ランキング1行ぶんのデータ
class LeaderboardEntry {
  final String uid;
  final String? nickname;
  final int vocab;
  final int rank;
  final bool isMe;

  const LeaderboardEntry({
    required this.uid,
    required this.nickname,
    required this.vocab,
    required this.rank,
    required this.isMe,
  });

  Map<String, dynamic> toJson() => {
        'uid': uid,
        'nickname': nickname,
        'vocab': vocab,
        'rank': rank,
        'isMe': isMe,
      };

  factory LeaderboardEntry.fromJson(Map<String, dynamic> json) =>
      LeaderboardEntry(
        uid: json['uid'] as String,
        nickname: json['nickname'] as String?,
        vocab: (json['vocab'] as num?)?.toInt() ?? 0,
        rank: (json['rank'] as num?)?.toInt() ?? 0,
        isMe: json['isMe'] == true,
      );
}

CollectionReference<Map<String, dynamic>> _leaderboardRef() =>
    FirebaseFirestore.instance.collection('leaderboard');

String? _readNickname(Map<String, dynamic>? data) {
  final name = (data?['nickname'] as String?)?.trim();
  return (name == null || name.isEmpty) ? null : name;
}

/// 同じ帯の中で vocab が [vocab] より大きい人数 + 1。同点は同順位になる。
///
/// 全体順位にしない。語彙スコアの出発点は 4択16問の語彙テストで、上振れると
/// 帯をまたぐ（13〜16% が真値の2倍以上に測られる）。全体一本の並びだと測定の
/// 運が順位に直結してしまう。帯の中だけで比べれば、測定で移れるのは「どの帯で
/// 戦うか」までで、順位は日々の正誤でしか動かない。
Future<int> _rankOf(int vocab) async {
  final band = bandOf(vocab);
  final snapshot = await _leaderboardRef()
      .where('vocab', isGreaterThan: vocab)
      .where('vocab', isLessThanOrEqualTo: band.max ?? _vocabCeiling)
      .count()
      .get();
  return (snapshot.count ?? 0) + 1;
}

/// 自分のニックネーム（サーバーが初回生成時にタイ人名を自動採番する）
final myNicknameProvider = StreamProvider<String?>((ref) {
  final uid = ref.watch(authUidProvider).valueOrNull;
  if (uid == null) return Stream.value(null);

  return _leaderboardRef()
      .doc(uid)
      .snapshots()
      .map((doc) => _readNickname(doc.data()));
});

/// 自分の順位。自分より vocab が大きい人数 + 1。
///
/// スコアが0（＝まだ例文を生成していない）のときは順位なし（null）。
final myRankProvider = FutureProvider<int?>((ref) async {
  final myVocab = ref.watch(vocabStatsProvider).valueOrNull?.estimatedVocab ?? 0;
  final uid = ref.watch(authUidProvider).valueOrNull;
  if (uid == null || myVocab <= 0) return null;

  final skipCache = ref.watch(leaderboardRefreshEpochProvider) > 0;
  if (!skipCache) {
    final cached = await _readCache(_myRankCacheKey, uid, myVocab);
    if (cached is num) return cached.toInt();
  }

  final rank = await _rankOf(myVocab);
  await _writeCache(_myRankCacheKey, uid, myVocab, rank);
  return rank;
});

/// 上限なしの帯を範囲クエリで表すための天井
const int _vocabCeiling = 1 << 30;

/// 全員が同じスコアで並ぶ幅 1 の帯（free の上限）かどうか。
bool isTiedBand(({int min, int? max}) band) => band.max == band.min;

/// [vocab] が属する帯。どの帯にも入らない値（0以下）は最下段に寄せる。
({int min, int? max}) bandOf(int vocab) {
  for (final band in vocabBands) {
    if (vocab >= band.min && vocab <= (band.max ?? _vocabCeiling)) return band;
  }
  return vocabBands.first;
}

/// 語彙スコアの帯。free は 100 でキャップされるのでそこだけ単独の帯にする
/// （100 に人が積み上がるため、他の帯と混ぜると分布が読めなくなる）。
const List<({int min, int? max})> vocabBands = [
  (min: 1, max: 99),
  (min: 100, max: 100),
  (min: 101, max: 300),
  (min: 301, max: 600),
  (min: 601, max: 1000),
  (min: 1001, max: null),
];

/// 分布1帯ぶん
class VocabBand {
  final int min;
  final int? max;
  final int count;
  final bool isMine;

  const VocabBand({
    required this.min,
    required this.max,
    required this.count,
    required this.isMine,
  });

  Map<String, dynamic> toJson() =>
      {'min': min, 'max': max, 'count': count, 'isMine': isMine};

  factory VocabBand.fromJson(Map<String, dynamic> json) => VocabBand(
        min: (json['min'] as num?)?.toInt() ?? 0,
        max: (json['max'] as num?)?.toInt(),
        count: (json['count'] as num?)?.toInt() ?? 0,
        isMine: json['isMine'] == true,
      );
}

/// 語彙スコアの分布と全体人数・最高スコア
class VocabDistribution {
  final List<VocabBand> bands;
  final int total;

  const VocabDistribution({required this.bands, required this.total});

  Map<String, dynamic> toJson() => {
        'total': total,
        'bands': bands.map((band) => band.toJson()).toList(),
      };

  factory VocabDistribution.fromJson(Map<String, dynamic> json) =>
      VocabDistribution(
        total: (json['total'] as num?)?.toInt() ?? 0,
        bands: ((json['bands'] as List?) ?? const [])
            .map((band) => VocabBand.fromJson(band as Map<String, dynamic>))
            .toList(),
      );

  /// 自分の帯の中で上位何%か（1未満は1に丸める）。順位が無いときは null。
  ///
  /// 母数は全体ではなく自分の帯。順位（[myRankProvider]）が帯の中の順位なので、
  /// 全体人数で割ると必ず実際より上位に見えてしまう。
  int? percentile(int? rank) {
    if (rank == null) return null;
    final mine = bands.where((band) => band.isMine).firstOrNull;
    if (mine == null || mine.count <= 0) return null;
    // 幅 1 の帯（free の上限 100）は全員同点。ここで順位から割合を出すと
    // 誰もが「上位1%」になってしまうので出さない。
    if (mine.min == mine.max) return null;
    return (rank / mine.count * 100).ceil().clamp(1, 100);
  }
}

/// 帯ごとの人数を count() 集計で数える。
///
/// 帯の数だけクエリが要るが、count() は1000件ごとに1読み取りの課金なので
/// 母数が増えても実質ゼロに近い。
final vocabDistributionProvider =
    FutureProvider<VocabDistribution>((ref) async {
  final uid = ref.watch(authUidProvider).valueOrNull;
  final myVocab = ref.watch(vocabStatsProvider).valueOrNull?.estimatedVocab ?? 0;

  final skipCache = ref.watch(leaderboardRefreshEpochProvider) > 0;
  if (uid != null && !skipCache) {
    final cached = await _readCache(_distributionCacheKey, uid, myVocab);
    if (cached is Map<String, dynamic>) {
      return VocabDistribution.fromJson(cached);
    }
  }

  final counts = await Future.wait(vocabBands.map((band) => _leaderboardRef()
      .where('vocab', isGreaterThanOrEqualTo: band.min)
      .where('vocab', isLessThanOrEqualTo: band.max ?? _vocabCeiling)
      .count()
      .get()));

  // 自分の doc はサーバーが例文生成時に作る。まだ無い間も1人として数に入れる。
  final missingSelf = uid == null ||
      !(await _leaderboardRef().doc(uid).get()).exists;

  var total = 0;
  final bands = <VocabBand>[];
  for (var i = 0; i < vocabBands.length; i++) {
    final band = vocabBands[i];
    final mine = myVocab > 0 &&
        myVocab >= band.min &&
        myVocab <= (band.max ?? _vocabCeiling);
    final count = (counts[i].count ?? 0) + (mine && missingSelf ? 1 : 0);
    total += count;
    bands.add(VocabBand(
      min: band.min,
      max: band.max,
      count: count,
      isMine: mine,
    ));
  }

  final distribution = VocabDistribution(bands: bands, total: total);
  if (uid != null) {
    await _writeCache(
      _distributionCacheKey,
      uid,
      myVocab,
      distribution.toJson(),
    );
  }
  return distribution;
});

/// 自分と、その上下[leaderboardNeighborCount]人ぶんの行。
///
/// 全体一覧は出さない（母数の大半が free の同点で埋まり、上位は課金者に固定される）。
/// 見せるのは「自分がいまどのあたりか」と、すぐ上・すぐ下の相手だけ。
///
/// 境界は `>=` / `<=` で取る。`>` / `<` にすると自分と同点の相手が上下どちらの
/// クエリにも入らず、free が 100 語で密集したときに隣が誰も出なくなる。
/// 自分の doc（サーバーが例文生成時に作る）は結果から外し、手元のスコアで差し込む。
final leaderboardRowsProvider =
    FutureProvider<List<LeaderboardEntry>>((ref) async {
  final uid = ref.watch(authUidProvider).valueOrNull;
  final myVocab = ref.watch(vocabStatsProvider).valueOrNull?.estimatedVocab ?? 0;
  final myNickname = ref.watch(myNicknameProvider).valueOrNull;
  if (uid == null || myVocab <= 0) return const [];

  // 起動のたびに数え直さない。nickname だけは stream で来た最新に差し替える。
  final skipCache = ref.watch(leaderboardRefreshEpochProvider) > 0;
  if (!skipCache) {
    final cached = await _readCache(_rowsCacheKey, uid, myVocab);
    if (cached is List) {
      return cached
          .map((row) =>
              LeaderboardEntry.fromJson(row as Map<String, dynamic>))
          .map((row) => row.isMe
              ? LeaderboardEntry(
                  uid: row.uid,
                  nickname: myNickname ?? row.nickname,
                  vocab: row.vocab,
                  rank: row.rank,
                  isMe: true,
                )
              : row)
          .toList();
    }
  }

  // 自分の doc はサーバーが例文生成時に作る。まだ無い間は count() 集計に自分が
  // 入らないので、自分より下の行の順位が1つ繰り上がって見えてしまう。
  final myDoc = await _leaderboardRef().doc(uid).get();
  final missingSelf = !myDoc.exists;

  // 自分の doc も引っかかるので1件多く取る
  final limit = leaderboardNeighborCount + 1;
  // トップも周辺も自分の帯の中だけで取る。帯をまたぐと、申告レベルで上の帯に
  // 移った人がそのまま上位に並んでしまう。
  final band = bandOf(myVocab);
  final bandMax = band.max ?? _vocabCeiling;
  final topDocs = await _leaderboardRef()
      .where('vocab', isGreaterThanOrEqualTo: band.min)
      .where('vocab', isLessThanOrEqualTo: bandMax)
      .orderBy('vocab', descending: true)
      .limit(leaderboardTopCount)
      .get();
  final results = await Future.wait([
    _leaderboardRef()
        .where('vocab', isGreaterThanOrEqualTo: myVocab)
        .where('vocab', isLessThanOrEqualTo: bandMax)
        .orderBy('vocab')
        .limit(limit)
        .get(),
    _leaderboardRef()
        .where('vocab', isLessThanOrEqualTo: myVocab)
        .where('vocab', isGreaterThanOrEqualTo: band.min)
        .orderBy('vocab', descending: true)
        .limit(limit)
        .get(),
  ]);

  List<QueryDocumentSnapshot<Map<String, dynamic>>> pick(int index) => results[
          index]
      .docs
      .where((doc) => doc.id != uid)
      .take(leaderboardNeighborCount)
      .toList();

  // 上側は自分に近い順に取っているので、表示のために反転する
  final above = pick(0).reversed.toList();
  final below = pick(1);

  Future<LeaderboardEntry> toEntry(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final vocab = (doc.data()['vocab'] as num?)?.toInt() ?? 0;
    // 自分が未登録なら、自分より下の行には自分のぶんを足して数える
    final offset = (missingSelf && vocab < myVocab) ? 1 : 0;
    return LeaderboardEntry(
      uid: doc.id,
      nickname: _readNickname(doc.data()),
      vocab: vocab,
      rank: await _rankOf(vocab) + offset,
      isMe: false,
    );
  }

  final top = topDocs.docs.where((doc) => doc.id != uid).toList();

  final entries = [
    ...await Future.wait(top.map(toEntry)),
    ...await Future.wait(above.map(toEntry)),
    LeaderboardEntry(
      uid: uid,
      nickname: myNickname,
      vocab: myVocab,
      rank: await _rankOf(myVocab),
      isMe: true,
    ),
    ...await Future.wait(below.map(toEntry)),
  ];

  // 自分が上位に近いと、トップ3と周辺の窓が重なる。同じ人を2度出さない。
  final seen = <String>{};
  final merged = entries.where((entry) => seen.add(entry.uid)).toList()
    ..sort((a, b) => b.vocab.compareTo(a.vocab));
  await _writeCache(
    _rowsCacheKey,
    uid,
    myVocab,
    merged.map((entry) => entry.toJson()).toList(),
  );
  return merged;
});
