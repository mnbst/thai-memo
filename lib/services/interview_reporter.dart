// =============================================================================
// interview_reporter.dart
// オンボーディング直後のヒアリング回答を users/{uid} へ書く。
//
// 回答は端末（SharedPreferences）にも残るが、それだけだと「どんな人が入って
// きて、どこで消えたか」を後から突き合わせられない。users doc に置けば、
// tier・継続日数・estimated_vocab と同じ場所で読めるので、prod-analytics の
// 集計から属性別の定着を出せる。
//
// GA4 側にも同じ回答を送っている（interview イベント）が、あちらは
// 「オンボの何問目で落ちたか」を見るためのもので、個々のユーザーを追えない。
// 属性 × 定着はこちらで見る。
//
// interview 以下はサーバー管理フィールドではないので firestore.rules の
// 拒否リストに掛からない。ルール変更は不要。
// =============================================================================

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/config/app_config.dart';

class InterviewReporter {
  /// インスタンスの解決は [report] の中まで遅らせる。コンストラクタで
  /// `FirebaseFirestore.instance` を掴むと、初期化前に生成しただけで
  /// 例外になり、呼び出し元（ヒアリング完了処理）ごと止まる。
  const InterviewReporter({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _firestore = firestore,
        _auth = auth;

  final FirebaseFirestore? _firestore;
  final FirebaseAuth? _auth;

  /// 端末に残っているヒアリング回答を users doc へ送る。
  ///
  /// ヒアリングを通過していない人、既に送信済みの人には何もしない。
  /// 失敗しても握り潰す（同期済みフラグを立てないので次の起動で送り直される）。
  /// 学習の導線は止めないので、呼び出し側は結果を待たなくてよい。
  Future<void> report() async {
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool(AppConfig.prefKeyInterviewCompleted) ?? false)) return;
    if (prefs.getBool(AppConfig.prefKeyInterviewSynced) ?? false) return;

    final answers = <String, String>{};
    for (final key in AppConfig.interviewQuestionKeys) {
      final value = prefs.getString('${AppConfig.prefKeyInterviewPrefix}$key');
      if (value != null) answers[key] = value;
    }

    try {
      final auth = _auth ?? FirebaseAuth.instance;
      final uid = auth.currentUser?.uid;
      if (uid == null) return;
      final firestore = _firestore ?? FirebaseFirestore.instance;
      await firestore.collection('users').doc(uid).set(
        {
          'interview': answers,
          // 全問スキップ（answers が空）も記録に残す。答えなかったこと自体が
          // 見たい情報なので、フィールドごと消さない。
          'interview_answer_count': answers.length,
          'interview_answered_at': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      await prefs.setBool(AppConfig.prefKeyInterviewSynced, true);
    } catch (_) {
      // 通信断・権限エラー・Firebase 未初期化（テスト）。次回起動で再送する。
    }
  }
}
