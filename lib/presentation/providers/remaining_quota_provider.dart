import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/firebase_auth_service.dart';

/// Firestore users/{uid}.remaining_sentences をリアルタイム取得
final remainingSentencesProvider = StreamProvider<int>((ref) {
  final uid = FirebaseAuthService.instance.currentUser?.uid;
  if (uid == null) return Stream.value(0);

  return FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .snapshots()
      .map((doc) {
    final data = doc.data();
    return (data?['remaining_sentences'] as num?)?.toInt() ?? 0;
  });
});

/// Firestore users/{uid}.remaining_quizzes をリアルタイム取得
final remainingQuizzesProvider = StreamProvider<int>((ref) {
  final uid = FirebaseAuthService.instance.currentUser?.uid;
  if (uid == null) return Stream.value(0);

  return FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .snapshots()
      .map((doc) {
    final data = doc.data();
    return (data?['remaining_quizzes'] as num?)?.toInt() ?? 0;
  });
});
