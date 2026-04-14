import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'remaining_quota_provider.dart';

/// 語彙スコアの状態
class VocabStats {
  final int estimatedVocab;

  const VocabStats({this.estimatedVocab = 0});
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
    );
  });
});
