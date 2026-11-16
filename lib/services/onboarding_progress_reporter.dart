// =============================================================================
// onboarding_progress_reporter.dart
// 初回導線の各画面に入った・抜けた時刻を users/{uid}.onboarding に残す。
//
// GA4 のファネルは人数しか出ず、生成まで届かなかった人が使い方ガイドと
// ペイウォールのどちらで閉じたかを1人ずつ追えない。users doc に段ごとの
// 時刻を置けば、`*_open` はあるのに対の `*_done` が無い段で抜けたと分かる。
//
// 値は serverTimestamp。オフラインで書いたものは送れた時刻になる。
// onboarding はサーバー管理フィールドではないので firestore.rules の
// 拒否リストに掛からない。失敗しても学習の導線は止めない（再送もしない）。
// =============================================================================

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class OnboardingProgressReporter {
  const OnboardingProgressReporter();

  /// step: guide_open / guide_done / vocab_test_open / vocab_test_done /
  /// vocab_test_auto_skip / paywall_open / paywall_done / generate_start
  Future<void> mark(String step) async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      await FirebaseFirestore.instance.collection('users').doc(uid).set(
        {
          'onboarding': {step: FieldValue.serverTimestamp()},
        },
        SetOptions(merge: true),
      );
    } catch (_) {
      // 通信断・権限エラー・Firebase 未初期化（テスト）。計測なので握り潰す。
    }
  }
}
