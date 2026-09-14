import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../data/models/thai_sentence.dart';
import 'daily_sentence_service.dart';

/// 完了済みセットIDの保持数。Firestore doc の肥大化を防ぎつつ、
/// サーバー側の sentence doc 保持期間より長く覚えていられる幅。
const int maxCompletedSetIds = 64;

/// 直近 [maxCompletedSetIds] 件だけ残す。ローカルと Firestore で同じ規則を使う。
List<String> trimCompletedSetIds(Iterable<String> ids) {
  final list = ids.toList();
  return list.length <= maxCompletedSetIds
      ? list
      : list.sublist(list.length - maxCompletedSetIds);
}

class DailySetRef {
  const DailySetRef({required this.setId, required this.sentenceIds});

  /// 例文の実体はIDだけ持つ。本文はローカルDBか Firestore から引き直す。
  factory DailySetRef.fromSentences(
    String setId,
    List<ThaiSentence> sentences,
  ) =>
      DailySetRef(
        setId: setId,
        sentenceIds:
            [for (final s in sentences) s.id].whereType<String>().toList(),
      );

  final String setId;
  final List<String> sentenceIds;

  /// この並びでの例文の位置。載っていなければ null。
  int? positionOf(String? sentenceId) {
    if (sentenceId == null) return null;
    final found = sentenceIds.indexOf(sentenceId);
    return found < 0 ? null : found;
  }

  /// [candidates] のうち、この並びで最も先へ進んでいる1本。
  /// どれも載っていなければ先頭（＝まだ読んでいない扱い）。
  String? furthestOf(Iterable<String?> candidates) {
    if (sentenceIds.isEmpty) return null;
    var furthest = 0;
    for (final id in candidates) {
      final at = positionOf(id);
      if (at != null && at > furthest) furthest = at;
    }
    return sentenceIds[furthest];
  }

  Map<String, dynamic> toJson() => {
        'set_id': setId,
        'sentence_ids': sentenceIds,
      };

  static DailySetRef? fromJson(Object? value) {
    if (value is! Map) return null;
    final setId = value['set_id'];
    final ids = value['sentence_ids'];
    if (setId is! String || setId.isEmpty || ids is! List) return null;
    final sentenceIds = ids.whereType<String>().toList();
    if (sentenceIds.isEmpty) return null;
    return DailySetRef(setId: setId, sentenceIds: sentenceIds);
  }
}

class DailySetProgressSnapshot {
  const DailySetProgressSnapshot({
    this.active,
    this.activeSentenceId,
    this.pending = const [],
    this.completedSetIds = const [],
  });

  final DailySetRef? active;

  /// カーソルが指している例文ID。位置の正本はこれだけで、番号は並びから引く。
  ///
  /// 番号を持ち回ると、保存時と並びが1本違うだけで隣の例文を指す（欠けた1本を
  /// 拾い直した側を採ったとき、位置が先へずれる）。
  final String? activeSentenceId;

  final List<DailySetRef> pending;
  final List<String> completedSetIds;

  bool get isEmpty =>
      active == null && pending.isEmpty && completedSetIds.isEmpty;

  /// [active] の並びでの位置。表示と、番号しか読めない旧バージョン向け。
  int get activeIndex => active?.positionOf(activeSentenceId) ?? 0;

  /// ローカル（SharedPreferences）用。そのまま jsonEncode できる形にする。
  ///
  /// active_index は読まないが、書くのはやめない。1.5.0 以前のクライアントが
  /// 同じ doc を読むと、無ければセットの先頭から読み直しになる。
  Map<String, dynamic> toJson() => {
        'active': active?.toJson(),
        'active_index': activeIndex,
        'active_sentence_id': activeSentenceId,
        'pending': [for (final set in pending) set.toJson()],
        'completed_set_ids': completedSetIds,
      };

  /// Firestore 用。更新時刻はサーバー側で打つ。
  Map<String, dynamic> toFirestore() => {
        ...toJson(),
        'updated_at': FieldValue.serverTimestamp(),
      };

  static DailySetProgressSnapshot fromJson(Map<String, dynamic> data) {
    final pending = <DailySetRef>[];
    for (final value in (data['pending'] as List?) ?? const []) {
      final set = DailySetRef.fromJson(value);
      if (set != null) pending.add(set);
    }
    final active = DailySetRef.fromJson(data['active']);
    var anchorId = data['active_sentence_id'] as String?;
    if ((anchorId == null || anchorId.isEmpty) && active != null) {
      // 1.5.0 以前は番号だけを保存していた。その並びで読み替える。
      final index = (data['active_index'] as num?)?.toInt() ?? 0;
      if (index >= 0 && index < active.sentenceIds.length) {
        anchorId = active.sentenceIds[index];
      }
    }
    return DailySetProgressSnapshot(
      active: active,
      activeSentenceId: anchorId,
      pending: pending,
      completedSetIds: ((data['completed_set_ids'] as List?) ?? const [])
          .whereType<String>()
          .toList(),
    );
  }
}

abstract class DailySetProgressStore {
  /// リモート状態とマージした正本を返す。通信失敗時は null。
  Future<DailySetProgressSnapshot?> merge(DailySetProgressSnapshot local);

  /// 配信docから例文を引き直す。ローカルDBは呼び出し側が先に見る。
  Future<ThaiSentence?> fetchSentence(String id);

  /// 直近の配信セットの並びを配信docから組み直す。進行位置を失った端末を
  /// 救うためだけの経路で、取り込み済みかどうかは問わない（取り込み済みの
  /// 配信は DailySentenceService.syncAll が返さないので、そこからは辿れない）。
  ///
  /// 既定は「組み直さない」。救済はクラウドの配信docを持つ実装だけの仕事で、
  /// 通常の復元経路はこれに依存しない。
  Future<DailySetRef?> fetchLatestDeliveredSet() async => null;
}

class FirestoreDailySetProgressStore implements DailySetProgressStore {
  FirestoreDailySetProgressStore({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  CollectionReference<Map<String, dynamic>>? _userCollection(String name) {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return null;
    return _firestore.collection('users').doc(uid).collection(name);
  }

  @override
  Future<DailySetProgressSnapshot?> merge(
    DailySetProgressSnapshot local,
  ) async {
    final ref = _userCollection('learning_state')?.doc('daily_sets');
    if (ref == null) return null;
    try {
      return await _firestore.runTransaction((transaction) async {
        final data = (await transaction.get(ref)).data();
        final remote = data == null
            ? const DailySetProgressSnapshot()
            : DailySetProgressSnapshot.fromJson(data);
        final merged = mergeDailySetProgress(remote, local);
        transaction.set(ref, merged.toFirestore());
        return merged;
      });
    } catch (_) {
      return null;
    }
  }

  @override
  Future<ThaiSentence?> fetchSentence(String id) async {
    try {
      final doc = await _userCollection('sentences')?.doc(id).get();
      final data = doc?.data();
      return data == null ? null : DailySentenceService.toSentence(id, data);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<DailySetRef?> fetchLatestDeliveredSet() async {
    final collection = _userCollection('sentences');
    if (collection == null) return null;
    try {
      // 絞り込みは取り込み経路（DailySentenceService）と同じ形にする。
      // 別の形にすると複合インデックスをもう1本作ることになる。
      final since = DateTime.now().subtract(
        const Duration(days: deliveredSetLookbackDays),
      );
      final snapshot = await collection
          .where('daily', isEqualTo: true)
          .where('created_at', isGreaterThan: Timestamp.fromDate(since))
          .get();

      final docs = [
        for (final doc in snapshot.docs) MapEntry(doc.id, doc.data()),
      ];
      return latestDeliveredSetRef(docs);
    } catch (_) {
      return null;
    }
  }
}

/// 配信docの束から、いちばん新しいセットの並びを取り出す。
///
/// セットの新しさは、そのセットに属する doc の created_at の最大で測る。
/// 並びは DailySentenceService と同じ daily_set_index の昇順。
DailySetRef? latestDeliveredSetRef(
  List<MapEntry<String, Map<String, dynamic>>> docs,
) {
  final newest = <String, DateTime>{};
  for (final doc in docs) {
    final setId = DailySentenceService.setIdOf(doc.key, doc.value);
    final createdAt = doc.value['created_at'];
    final date = createdAt is Timestamp
        ? createdAt.toDate()
        : DateTime.fromMillisecondsSinceEpoch(0);
    final previous = newest[setId];
    if (previous == null || date.isAfter(previous)) newest[setId] = date;
  }
  if (newest.isEmpty) return null;

  final latestSetId = newest.entries
      .reduce((a, b) => a.value.isAfter(b.value) ? a : b)
      .key;
  final members = DailySentenceService.orderSetMembers(latestSetId, docs);
  final ids = [for (final member in members) member.key];
  if (ids.isEmpty) return null;
  return DailySetRef(setId: latestSetId, sentenceIds: ids);
}

/// 端末間競合を単調にマージする。完了済みは復活させず、同一セットの位置は
/// 大きい方を採用する。異なる進行中セットはリモートを先にして片方を待機へ回す。
DailySetProgressSnapshot mergeDailySetProgress(
  DailySetProgressSnapshot remote,
  DailySetProgressSnapshot local,
) {
  final completed = <String>{
    ...remote.completedSetIds,
    ...local.completedSetIds,
  };
  final refs = <DailySetRef>[
    if (remote.active != null) remote.active!,
    if (local.active != null) local.active!,
    ...remote.pending,
    ...local.pending,
  ];
  final unique = <String, DailySetRef>{};
  for (final ref in refs) {
    if (!completed.contains(ref.setId)) {
      final previous = unique[ref.setId];
      if (previous == null ||
          ref.sentenceIds.length > previous.sentenceIds.length) {
        unique[ref.setId] = ref;
      }
    }
  }

  DailySetRef? active;
  final remoteActive = remote.active;
  final localActive = local.active;
  if (remoteActive != null && unique.containsKey(remoteActive.setId)) {
    active = unique.remove(remoteActive.setId);
  } else if (localActive != null && unique.containsKey(localActive.setId)) {
    active = unique.remove(localActive.setId);
  } else if (unique.isNotEmpty) {
    active = unique.values.first;
    unique.remove(active.setId);
  }

  return DailySetProgressSnapshot(
    active: active,
    // 単調性は「採用した並びでの位置」で比べる。別セットのIDはこの並びに
    // 載っていないので、両端末ぶんを渡しても取り違えない。
    activeSentenceId: active?.furthestOf(
      [remote.activeSentenceId, local.activeSentenceId],
    ),
    pending: unique.values.toList(),
    completedSetIds: trimCompletedSetIds(completed),
  );
}

/// 学習中の端末へクラウド状態を取り込む。ただし、画面に出しているセットと
/// カーソルは動かさない。別端末が先へ進んでいても、読んでいる例文を突然
/// 差し替えたり、次セットの1本目を飛ばしたりしないための foreground merge。
///
/// クラウド側の次セットと待機セットは、現在セットの後ろへ欠落なく取り込む。
DailySetProgressSnapshot mergeDailySetProgressPreservingLocalActive(
  DailySetProgressSnapshot cloud,
  DailySetProgressSnapshot local,
) {
  final localActive = local.active;
  // 通信中にこの端末がセットを完了した場合、その completed をクラウド結果へ
  // 重ね直す。cloud をそのまま返すと、完了直前の active が復活する。
  if (localActive == null) return mergeDailySetProgress(cloud, local);

  final completed = <String>{
    ...cloud.completedSetIds,
    ...local.completedSetIds,
  }..remove(localActive.setId);

  var active = localActive;
  final cloudRefs = <DailySetRef>[
    if (cloud.active != null) cloud.active!,
    ...cloud.pending,
  ];
  for (final ref in cloudRefs) {
    if (ref.setId == localActive.setId &&
        ref.sentenceIds.length > active.sentenceIds.length) {
      active = ref;
    }
  }

  final pending = <String, DailySetRef>{};
  for (final ref in [...local.pending, ...cloudRefs]) {
    if (ref.setId == active.setId || completed.contains(ref.setId)) continue;
    final previous = pending[ref.setId];
    if (previous == null ||
        ref.sentenceIds.length > previous.sentenceIds.length) {
      pending[ref.setId] = ref;
    }
  }

  return DailySetProgressSnapshot(
    active: active,
    // 読んでいる1本はそのまま。クラウド側の長い並びを採っても、位置はIDで
    // 引き直されるので動かない。
    activeSentenceId: local.activeSentenceId,
    pending: pending.values.toList(),
    completedSetIds: trimCompletedSetIds(completed),
  );
}
