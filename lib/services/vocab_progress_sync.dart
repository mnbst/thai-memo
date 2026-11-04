// =============================================================================
// vocab_progress_sync.dart
// 語彙一覧の習熟度をサーバーから差分で取り、端末の DB に写す。
// 語が多くても毎回全件を読まないよう、続きの位置（cursor）を覚えておく。
// =============================================================================

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/models/vocab_word.dart';

class VocabProgressSync {
  static const String ownerKey = 'vocab_progress_owner';
  static const String cursorKey = 'vocab_progress_cursor';

  /// 1回の同期で読むページの上限（500語 × 40 で頻度表の全語を超える）。
  static const int maxPages = 40;

  /// 学習データの初期化で呼ぶ。次の同期で最初から取り直す。
  static Future<void> forget(SharedPreferences prefs) async {
    await prefs.remove(ownerKey);
    await prefs.remove(cursorKey);
  }

  /// [uid] の差分を取り込む。通信に失敗しても端末の内容はそのまま残す。
  static Future<void> run({
    required String uid,
    required SharedPreferences prefs,
    required Future<VocabProgressPage> Function(String? cursor) fetch,
    required Future<void> Function(List<VocabWord> words) save,
    required Future<void> Function() clear,
  }) async {
    // 別のアカウントの語が混ざらないよう、持ち主が替わったら捨てて取り直す。
    if (prefs.getString(ownerKey) != uid) {
      await clear();
      await prefs.remove(cursorKey);
      await prefs.setString(ownerKey, uid);
    }
    var cursor = prefs.getString(cursorKey);
    try {
      for (var i = 0; i < maxPages; i++) {
        final page = await fetch(cursor);
        await save(page.words);
        cursor = page.nextCursor;
        if (cursor != null) await prefs.setString(cursorKey, cursor);
        if (page.done) break;
      }
    } catch (e) {
      debugPrint('VocabProgressSync: $e');
    }
  }
}
