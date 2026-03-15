import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Firebase Auth の uid をリアクティブに提供
final authUidProvider = StreamProvider<String?>((ref) {
  return FirebaseAuth.instance.authStateChanges().map((user) => user?.uid);
});

/// Firestore users/{uid}.remaining_sentences をリアルタイム取得
final remainingSentencesProvider = StreamProvider<int>((ref) {
  final uidAsync = ref.watch(authUidProvider);
  final uid = uidAsync.valueOrNull;
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
  final uidAsync = ref.watch(authUidProvider);
  final uid = uidAsync.valueOrNull;
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
