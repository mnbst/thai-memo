// =============================================================================
// sentence_remote_state.dart
// お気に入り・削除を users/{uid}/sentences/{id} に書き、ほかの端末へ伝える。
//
// 書くのは favorite / deleted と updated_at だけ（firestore.rules で制限）。
// updated_at は差分同期のカーソル（DailySentenceService の syncAll）。
// 待たずに投げる。通信できないときは Firestore の端末キャッシュに溜まり、
// つながったときに送られる。
// =============================================================================

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class SentenceRemoteState {
  SentenceRemoteState({FirebaseFirestore? firestore, FirebaseAuth? auth})
      : _firestoreOverride = firestore,
        _authOverride = auth;

  final FirebaseFirestore? _firestoreOverride;
  final FirebaseAuth? _authOverride;

  void markFavorite(String id, bool isFavorite) =>
      _write([id], {'favorite': isFavorite});

  void markDeleted(List<String> ids) => _write(ids, {'deleted': true});

  void _write(List<String> ids, Map<String, Object> fields) {
    if (ids.isEmpty) return;
    try {
      final uid = (_authOverride ?? FirebaseAuth.instance).currentUser?.uid;
      if (uid == null) return;
      final firestore = _firestoreOverride ?? FirebaseFirestore.instance;
      final sentences =
          firestore.collection('users').doc(uid).collection('sentences');
      final data = {...fields, 'updated_at': FieldValue.serverTimestamp()};
      for (final id in ids) {
        // 1件ずつ送る。まとめると、サーバーに無い例文（旧版で消えたもの）が
        // 1件混じっただけで全部落ちる。伝わらないのはほかの端末への反映だけ
        // なので、失敗はログだけ残す。
        unawaited(sentences.doc(id).update(data).catchError((Object e) {
          debugPrint('SentenceRemoteState: write failed for $id: $e');
        }));
      }
    } catch (e) {
      // Firebase 未初期化（テスト）など。端末の操作は済んでいるので止めない。
      debugPrint('SentenceRemoteState: write skipped: $e');
    }
  }
}
