import 'package:flutter/material.dart';

/// アプリの言語。UI文言と学習コンテンツ（訳文・単語の意味）の両方を決める。
/// UI言語と訳文言語は分けない。
enum AppLanguage {
  ja,
  en;

  /// SharedPreferences / Firestore / CF 引数に載せる値
  String get code => name;

  Locale get locale => Locale(name);

  /// dev ビルドの言語切替ピッカーでの表示名。自言語で書く（切替前でも読めるように）。
  String get displayName => switch (this) {
        AppLanguage.ja => '日本語',
        AppLanguage.en => 'English',
      };

  static AppLanguage fromCode(String? code) => AppLanguage.values.firstWhere(
        (e) => e.name == code,
        orElse: () => AppLanguage.ja,
      );

  /// ダウンロード元のストア地域から初期言語を決める。**既定は ja**。
  /// 日本以外のストアだと確認できたときだけ en に倒す。
  ///
  /// 端末ロケールは使わない。ロケールで判定すると海外在住の日本語話者が ja 側に
  /// 入り、日本市場のセグメントに混ざるため、判定軸はストア地域に一本化する。
  ///
  /// iOS(`SKStorefront`) は ISO 3166-1 Alpha-3（`JPN`）、Android(`BillingConfig`)
  /// は Alpha-2（`JP`）を返すので両方を受ける。取得失敗（null）は ja のまま
  /// ＝ 現行ユーザーの挙動を変えない安全側に倒す。
  static AppLanguage fromStorefront(String? countryCode) {
    final code = countryCode?.trim().toUpperCase() ?? '';
    if (code.isEmpty) return AppLanguage.ja;
    return const {'JP', 'JPN'}.contains(code) ? AppLanguage.ja : AppLanguage.en;
  }
}
