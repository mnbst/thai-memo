// =============================================================================
// pronunciation_quota_provider.dart
// 発音練習の1日あたり回数（free のみ）。
//
// 判定は端末内で完結し、サーバ原価がゼロなので、カウンタも端末ローカルに置く。
// 改ざんされても失うものが無く、Cloud Functions を挟む理由がない。
// リセットは端末のローカル日付が変わったとき。
// =============================================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// free ユーザーが1日に受けられる発音チェックの回数。
///
/// 「良さは分かるが足りない」に着地させるための数。採点が出たときだけ1消費する
/// （録音に失敗した回は消費しない）。
const freeDailyPronunciationChecks = 5;

const _countKey = 'pronunciation_checks_count';
const _dateKey = 'pronunciation_checks_date';

final pronunciationQuotaProvider =
    StateNotifierProvider<PronunciationQuotaController, int>((ref) {
  return PronunciationQuotaController()..load();
});

/// 今日すでに使った回数を持つ。
class PronunciationQuotaController extends StateNotifier<int> {
  PronunciationQuotaController() : super(0);

  static String _today() {
    final now = DateTime.now();
    return '${now.year}-${now.month}-${now.day}';
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(_dateKey) != _today()) {
      state = 0;
      return;
    }
    state = prefs.getInt(_countKey) ?? 0;
  }

  /// 採点が1回成立したときに呼ぶ。
  Future<void> consume() async {
    final prefs = await SharedPreferences.getInstance();
    final today = _today();
    // 日付をまたいだまま画面を開き続けている場合があるので、消費のたびに見る。
    final used = prefs.getString(_dateKey) == today
        ? (prefs.getInt(_countKey) ?? 0)
        : 0;
    final next = used + 1;
    await prefs.setString(_dateKey, today);
    await prefs.setInt(_countKey, next);
    if (!mounted) return;
    state = next;
  }

  int get remaining {
    final left = freeDailyPronunciationChecks - state;
    return left < 0 ? 0 : left;
  }
}
