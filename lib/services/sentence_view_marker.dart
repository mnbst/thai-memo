// =============================================================================
// sentence_view_marker.dart
// 画面に出した例文へ既読（viewed=true）を付ける。
//
// まとめクイズの出題元はサーバー側の users/{uid}/sentences で、そこには
// まだ読んでいない例文も入っている（配信したが開いていない、生成の途中で
// アプリが終了した、など）。既読を返しておかないと、見たことのない例文が
// クイズに出る。
//
// 書き込みは users/{uid}/sentences/{id} の viewed だけ（firestore.rules で
// true への変更のみ許可）。通信できなければ端末に溜め、次の起動で流す。
// =============================================================================

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SentenceViewMarker {
  SentenceViewMarker({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _firestoreOverride = firestore,
        _authOverride = auth;

  /// 既定の共有インスタンス。どの画面から読んでも同じ待ち行列を使う。
  static final SentenceViewMarker instance = SentenceViewMarker();

  /// まだ送れていない例文ID。
  static const String pendingKey = 'viewed_sentence_pending';

  /// 送信済みの例文ID。同じ例文を開くたびに書かないために覚えておく。
  static const String sentKey = 'viewed_sentence_sent';

  /// 覚えておく送信済みIDの上限。サーバーは30日で例文を消すので、それ以上
  /// 覚えても使い道がない（1日あたり配信5本＋生成ぶん）。
  static const int sentLimit = 300;

  /// 溜めておく未送信IDの上限。ここを超えるほど溜まるのは長い通信断で、
  /// 古い例文はサーバー側の保持期間から外れていく。古い方から捨てる。
  static const int pendingLimit = 100;

  final FirebaseFirestore? _firestoreOverride;
  final FirebaseAuth? _authOverride;

  Future<void> _tail = Future.value();

  Future<T> _serialized<T>(Future<T> Function() operation) async {
    final previous = _tail;
    final done = Completer<void>();
    _tail = done.future;
    await previous;
    try {
      return await operation();
    } finally {
      done.complete();
    }
  }

  /// 書き込みが落ち着くまで待つ（テストと、続けて読む経路のため）。
  Future<void> settled() => _serialized(() async {});

  /// 表示した例文を既読として記録する。
  ///
  /// 学習の導線を止めないので待たない。失敗しても次の起動の [flush] で回復する。
  void markViewed(String? sentenceId) {
    if (sentenceId == null || sentenceId.isEmpty) return;
    unawaited(_serialized(() => _enqueue(sentenceId)));
  }

  Future<void> _enqueue(String sentenceId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final sent = _read(prefs, sentKey);
      if (sent.contains(sentenceId)) return;

      final pending = _read(prefs, pendingKey);
      if (!pending.contains(sentenceId)) {
        pending.add(sentenceId);
        _trim(pending, pendingLimit);
        await prefs.setStringList(pendingKey, pending);
      }
      await _send(prefs, pending, sent);
    } catch (_) {
      // 端末保存もFirestoreも、失敗して困るのは既読の記録だけ。次回に回す。
    }
  }

  /// 溜まっている未送信ぶんを流す。起動時に1回呼ぶ。
  Future<void> flush() => _serialized(_flush);

  Future<void> _flush() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pending = _read(prefs, pendingKey);
      if (pending.isEmpty) return;
      await _send(prefs, pending, _read(prefs, sentKey));
    } catch (_) {
      // 次の起動で流す。
    }
  }

  /// [pending] を順に送り、結果を端末へ書き戻す（直列化の内側で呼ぶこと）。
  Future<void> _send(
    SharedPreferences prefs,
    List<String> pending,
    List<String> sent,
  ) async {
    final uid = (_authOverride ?? FirebaseAuth.instance).currentUser?.uid;
    if (uid == null) return;

    final sentences = (_firestoreOverride ?? FirebaseFirestore.instance)
        .collection('users')
        .doc(uid)
        .collection('sentences');

    final done = <String>[];
    for (final id in List<String>.from(pending)) {
      try {
        await sentences.doc(id).update({'viewed': true});
        done.add(id);
      } on FirebaseException catch (e) {
        // 消えた例文（30日で削除）は送りようがないので待ち行列から外す。
        // それ以外（通信断など）は残して次の起動で送り直す。
        if (e.code == 'not-found' || e.code == 'permission-denied') {
          pending.remove(id);
          continue;
        }
        break;
      } catch (_) {
        break;
      }
    }

    for (final id in done) {
      pending.remove(id);
      sent.add(id);
    }
    _trim(sent, sentLimit);
    await prefs.setStringList(pendingKey, pending);
    await prefs.setStringList(sentKey, sent);
  }

  List<String> _read(SharedPreferences prefs, String key) {
    try {
      return List<String>.from(prefs.getStringList(key) ?? const []);
    } catch (_) {
      // 旧バージョンが別の型で書いていた場合の保険。読めなければ空から始める。
      return [];
    }
  }

  /// 先頭（古い方）から捨てて [limit] 件に収める。
  void _trim(List<String> ids, int limit) {
    if (ids.length <= limit) return;
    ids.removeRange(0, ids.length - limit);
  }

  /// 学習データの初期化で呼ぶ。記録を消して最初からにする。
  Future<void> clear() => _serialized(() async {
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.remove(pendingKey);
          await prefs.remove(sentKey);
        } catch (_) {
          // 消せなくても既読が残るだけで、学習データ本体には影響しない。
        }
      });
}
