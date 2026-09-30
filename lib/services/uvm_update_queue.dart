// =============================================================================
// uvm_update_queue.dart
// クイズ回答の語彙モデル（UVM）更新を、送れるまで端末に溜めて送り直す。
//
// 回答は updateUvm でサーバーへ送る。ここが正本（語彙の P・estimated_vocab・
// 復習の出題）なので、送り損ねた回答はどの端末の進捗にも入らない。圏外や
// タイムアウトで落ちたぶんは端末に残し、次に送れたときに古い順に流す。
// =============================================================================

import 'dart:async';
import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 1件ぶんの送信。失敗したら例外を投げる。
typedef UvmSender = Future<void> Function(Map<String, dynamic> payload);

class UvmUpdateQueue {
  UvmUpdateQueue({FirebaseAuth? auth}) : _authOverride = auth;

  /// 既定の共有インスタンス。どの画面から使っても同じ待ち行列を通す。
  static final UvmUpdateQueue instance = UvmUpdateQueue();

  static String pendingKey(String uid) => 'uvm_update_pending_$uid';

  /// 溜めておく件数の上限。超えるほどの通信断では古い方から捨てる。
  static const int pendingLimit = 500;

  final FirebaseAuth? _authOverride;
  Future<void> _tail = Future.value();

  String? get _uid {
    try {
      return (_authOverride ?? FirebaseAuth.instance).currentUser?.uid;
    } catch (_) {
      return null;
    }
  }

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

  /// 回答を端末に積んでから送る。送れなければ積んだまま次の [flush] に回す。
  Future<void> submit(Map<String, dynamic> payload, UvmSender send) =>
      _serialized(() async {
        final uid = _uid;
        if (uid == null) return;
        try {
          final prefs = await SharedPreferences.getInstance();
          final pending = prefs.getStringList(pendingKey(uid)) ?? [];
          pending.add(jsonEncode(payload));
          if (pending.length > pendingLimit) {
            pending.removeRange(0, pending.length - pendingLimit);
          }
          await prefs.setStringList(pendingKey(uid), pending);
          await _flush(prefs, uid, send);
        } catch (e) {
          debugPrint('UvmUpdateQueue: submit failed: $e');
        }
      });

  /// 溜まっている回答を送る。起動時・復帰時に呼ぶ。
  Future<void> flush(UvmSender send) => _serialized(() async {
        final uid = _uid;
        if (uid == null) return;
        try {
          await _flush(await SharedPreferences.getInstance(), uid, send);
        } catch (e) {
          debugPrint('UvmUpdateQueue: flush failed: $e');
        }
      });

  /// 学習データの初期化・アカウント切替で呼ぶ。消したデータの回答は送らない。
  Future<void> clear(String uid) => _serialized(() async {
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.remove(pendingKey(uid));
        } catch (_) {}
      });

  /// 古い順に送り、送れた（または送っても無駄な）ぶんを外す。
  /// 通信系の失敗で止まったら、残りは次回に回す。
  Future<void> _flush(
    SharedPreferences prefs,
    String uid,
    UvmSender send,
  ) async {
    final pending = prefs.getStringList(pendingKey(uid)) ?? const <String>[];
    if (pending.isEmpty) return;
    var sent = 0;
    for (final raw in pending) {
      // 送っている途中でアカウントが替わったら、前の人の回答を新しい人へ送らない。
      if (_uid != uid) break;
      final Map<String, dynamic> payload;
      try {
        payload = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      } catch (_) {
        sent++;
        continue;
      }
      try {
        await send(payload);
      } catch (e) {
        if (isRetriableUvmError(e)) {
          debugPrint('UvmUpdateQueue: will retry: $e');
          break;
        }
        debugPrint('UvmUpdateQueue: dropped: $e');
      }
      sent++;
    }
    if (sent == 0) return;
    // 送っているあいだに積まれたぶんを消さないよう、読み直してから先頭を外す。
    final latest = prefs.getStringList(pendingKey(uid)) ?? const <String>[];
    await prefs.setStringList(
      pendingKey(uid),
      latest.length <= sent ? const [] : latest.sublist(sent),
    );
  }
}

/// 送り直せば通る見込みのある失敗か。
///
/// 中身が悪い・権限が無いものは何度送っても通らないので捨てる。
@visibleForTesting
bool isRetriableUvmError(Object error) {
  if (error is FirebaseFunctionsException) {
    return const {
      'unavailable',
      'deadline-exceeded',
      'internal',
      'unknown',
      'aborted',
      'resource-exhausted',
    }.contains(error.code);
  }
  // 通信層の例外（SocketException など）は送り直す。
  return true;
}
