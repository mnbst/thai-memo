import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/firebase_auth_service.dart';

/// 推定語彙数の状態
class VocabStats {
  final int estimatedVocab;
  final int vocabCount;

  const VocabStats({this.estimatedVocab = 0, this.vocabCount = 0});
}

/// Firestore users/{uid} から推定語彙数をリアルタイム取得（Premium限定機能）
final vocabStatsProvider = StreamProvider<VocabStats>((ref) {
  final uid = FirebaseAuthService.instance.currentUser?.uid;
  if (uid == null) return Stream.value(const VocabStats());

  return FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .snapshots()
      .map((doc) {
    final data = doc.data();
    if (data == null) return const VocabStats();
    return VocabStats(
      estimatedVocab: (data['estimated_vocab'] as num?)?.toInt() ?? 0,
      vocabCount: (data['vocab_count'] as num?)?.toInt() ?? 0,
    );
  });
});
