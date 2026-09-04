import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'remaining_quota_provider.dart';

/// 語彙スコアの状態
class VocabStats {
  final int estimatedVocab;

  /// 前回の語彙テスト日時（users/{uid}.vocab_test_at）。未受験は null。
  final DateTime? testedAt;

  /// 語彙テストで測った値（users/{uid}.vocab_test_vocab）。未受験は 0。
  /// estimated_vocab と違い free の上限で切り下げられないので、体験終了時に
  /// 「測った値 → 上限」の落差を出すのに使う。
  final int testedVocab;

  const VocabStats({
    this.estimatedVocab = 0,
    this.testedAt,
    this.testedVocab = 0,
  });
}

/// Firestore users/{uid} から語彙統計をリアルタイム取得
final vocabStatsProvider = StreamProvider<VocabStats>((ref) {
  final uid = ref.watch(authUidProvider).valueOrNull;
  if (uid == null) return Stream.value(const VocabStats());

  return FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .snapshots()
      .map((doc) {
    final data = doc.data();
    if (data == null) return const VocabStats();
    return VocabStats(
      estimatedVocab:
          ((data['estimated_vocab'] as num?)?.toInt() ?? 0).clamp(0, 1 << 31),
      testedAt: (data['vocab_test_at'] as Timestamp?)?.toDate(),
      testedVocab: (data['vocab_test_vocab'] as num?)?.toInt() ?? 0,
    );
  });
});
