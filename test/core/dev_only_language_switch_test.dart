/// 言語切替が dev ビルド限定であることを固定する。
///
/// 言語はストア地域で決まり、切り替えても生成済みの履歴は書き換わらない。
/// 実ユーザーに開くと1つの履歴に日英が混在するため、導線は AppConfig.isDev で
/// 閉じている。`if (AppConfig.isDev)` を外す変更をここで止める。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:thai_memo/core/config/app_config.dart';

void main() {
  test('AppConfig.isDev は prod / tester で false', () {
    // ENV は --dart-define で渡す。テストは既定（dev）で走る。
    expect(AppConfig.isDev, isTrue);
    expect(AppConfig.isProd, isFalse);
    expect(AppConfig.isTester, isFalse);
  });

  test('設定画面の言語切替は AppConfig.isDev で閉じている', () {
    final source =
        File('lib/presentation/screens/settings_screen.dart').readAsStringSync();

    expect(
      source.contains('if (AppConfig.isDev)'),
      isTrue,
      reason: '言語切替の導線が製品ビルドに出てしまう',
    );
    // 切替の入口は dev ゲートの内側にしか無いこと
    final gateIndex = source.indexOf('if (AppConfig.isDev)');
    final pickerCall = source.indexOf('_showLanguagePicker(');
    expect(gateIndex, greaterThanOrEqualTo(0));
    expect(
      pickerCall,
      greaterThan(gateIndex),
      reason: 'ゲートの外から _showLanguagePicker を呼んでいる',
    );
  });
}
