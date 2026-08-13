// =============================================================================
// app_version_reporter.dart
// 起動時に users/{uid} へアプリのバージョンを書く。
//
// サーバーから「この人のアプリは、その機能を持っているか」を判定するために要る。
// 例えばプレミアム体験を既存ユーザーへ後から配る場合、開放を伝えるダイアログを
// 持たない版に配ると、本人が気づかないまま体験が始まって終わる。配る前にここで
// 版を知り、告知できる版の人にだけ配る。
//
// tier などサーバー管理のフィールドは firestore.rules で拒否リストに入っている
// 一方、ここで書く app_version / app_build_number は対象外なのでクライアントから
// 書ける。ルール変更は不要。
// =============================================================================

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:package_info_plus/package_info_plus.dart';

class AppVersionReporter {
  AppVersionReporter({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  /// 現在のバージョンを users doc に記録する。
  ///
  /// 失敗しても何も壊れない（次の起動で書き直される）ので、呼び出し側は結果を
  /// 待つ必要がない。学習の導線を1msでも止めないため、例外は握り潰す。
  Future<void> report() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    try {
      final info = await PackageInfo.fromPlatform();
      await _firestore.collection('users').doc(uid).set(
        {
          'app_version': info.version,
          'app_build_number': info.buildNumber,
          'last_opened_at': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } catch (_) {
      // 通信断・プラットフォーム側の失敗。次回起動で回復する。
    }
  }
}
