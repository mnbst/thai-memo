import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'remaining_quota_provider.dart';

/// 語彙スコアの状態
class VocabStats {
  final int estimatedVocab;

  /// 前回の語彙テスト日時（users/{uid}.vocab_test_at）。未受験は null。
  final DateTime? testedAt;

  /// 語彙テストで測った値（users/{uid}.vocab_test_vocab）。未受験は 0。
  /// estimated_vocab と違いfreeの100語上限で切り下げないため、再測定結果の
  /// 表示に使う。
  final int testedVocab;

  const VocabStats({
    this.estimatedVocab = 0,
    this.testedAt,
    this.testedVocab = 0,
  });
}

/// users/{uid} から語彙統計をリアルタイム取得
///
/// listener は張らず、[userDocSnapshotProvider] の1本を Premium・クォータと共有する。
final vocabStatsProvider = StreamProvider<VocabStats>((ref) {
  final uid = ref.watch(authUidProvider).valueOrNull;
  if (uid == null) return Stream.value(const VocabStats());

  final docs = StreamController<UserDocSnapshot>();
  ref.onDispose(docs.close);
  ref.listen<AsyncValue<UserDocSnapshot>>(
    userDocSnapshotProvider,
    (_, next) {
      final doc = next.valueOrNull;
      if (doc != null && !docs.isClosed) docs.add(doc);
    },
    fireImmediately: true,
  );

  return _watchVocabStats(uid, docs.stream);
});

const _vocabCachePrefix = 'vocab_stats_';

Stream<VocabStats> _watchVocabStats(
  String uid,
  Stream<UserDocSnapshot> docs,
) async* {
  final prefs = await SharedPreferences.getInstance();
  final estimatedKey = '$_vocabCachePrefix${uid}_estimated';
  final testedKey = '$_vocabCachePrefix${uid}_tested';
  final testedAtKey = '$_vocabCachePrefix${uid}_tested_at';
  final cachedEstimated = prefs.getInt(estimatedKey);
  final cachedTested = prefs.getInt(testedKey);
  final cachedTestedAt = prefs.getInt(testedAtKey);
  final hasLocal = cachedEstimated != null;

  if (hasLocal) {
    yield VocabStats(
      estimatedVocab: cachedEstimated.clamp(0, 1 << 31),
      testedVocab: cachedTested ?? 0,
      testedAt: cachedTestedAt == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(cachedTestedAt),
    );
  }

  await for (final doc in docs) {
    // SharedPreferences のほうが新しい可能性があるため、起動直後にFirestoreの
    // 永続キャッシュが返す古い値では巻き戻さない。サーバー確認済み、または
    // 端末値を持っていない場合だけ採用する。
    if (hasLocal && doc.isFromCache) continue;
    final data = doc.data;
    final stats = data == null
        ? const VocabStats()
        : VocabStats(
            estimatedVocab: ((data['estimated_vocab'] as num?)?.toInt() ?? 0)
                .clamp(0, 1 << 31),
            testedAt: (data['vocab_test_at'] as Timestamp?)?.toDate(),
            testedVocab: (data['vocab_test_vocab'] as num?)?.toInt() ?? 0,
          );
    yield stats;
    unawaited(_cacheVocabStats(
      prefs,
      estimatedKey,
      testedKey,
      testedAtKey,
      stats,
    ));
  }
}

Future<void> _cacheVocabStats(
  SharedPreferences prefs,
  String estimatedKey,
  String testedKey,
  String testedAtKey,
  VocabStats stats,
) async {
  await prefs.setInt(estimatedKey, stats.estimatedVocab);
  await prefs.setInt(testedKey, stats.testedVocab);
  final testedAt = stats.testedAt;
  if (testedAt == null) {
    await prefs.remove(testedAtKey);
  } else {
    await prefs.setInt(testedAtKey, testedAt.millisecondsSinceEpoch);
  }
}
