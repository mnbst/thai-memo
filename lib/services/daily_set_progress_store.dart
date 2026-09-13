import 'dart:math' as math;

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
    this.activeIndex = 0,
    this.pending = const [],
    this.completedSetIds = const [],
  });

  final DailySetRef? active;
  final int activeIndex;
  final List<DailySetRef> pending;
  final List<String> completedSetIds;

  bool get isEmpty =>
      active == null && pending.isEmpty && completedSetIds.isEmpty;

  /// ローカル（SharedPreferences）用。そのまま jsonEncode できる形にする。
  Map<String, dynamic> toJson() => {
        'active': active?.toJson(),
        'active_index': activeIndex,
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
    return DailySetProgressSnapshot(
      active: DailySetRef.fromJson(data['active']),
      activeIndex: (data['active_index'] as num?)?.toInt() ?? 0,
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
  var index = 0;
  final remoteActive = remote.active;
  final localActive = local.active;
  if (remoteActive != null && unique.containsKey(remoteActive.setId)) {
    active = unique.remove(remoteActive.setId);
    index = localActive?.setId == remoteActive.setId
        ? math.max(remote.activeIndex, local.activeIndex)
        : remote.activeIndex;
  } else if (localActive != null && unique.containsKey(localActive.setId)) {
    active = unique.remove(localActive.setId);
    index = local.activeIndex;
  } else if (unique.isNotEmpty) {
    active = unique.values.first;
    unique.remove(active.setId);
  }

  return DailySetProgressSnapshot(
    active: active,
    activeIndex: index,
    pending: unique.values.toList(),
    completedSetIds: trimCompletedSetIds(completed),
  );
}
