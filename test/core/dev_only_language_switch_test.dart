/// 言語切替が製品ビルドに出ないことを固定する。
///
/// 言語はストア地域で決まり、切り替えても生成済みの履歴は書き換わらない。
/// 実ユーザーに開くと1つの履歴に日英が混在するため、導線は dev / tester だけに
/// 開く。**tester には出す**：言語は初回起動で1回決めて保存し以後は再評価しない
/// ので、サンドボックスのストア地域で en に落ちると戻す手段が無くなる。
/// ゲートを外す変更をここで止める。
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

  test('設定画面の言語切替は dev / tester だけに開いている', () {
    final source =
        File('lib/presentation/screens/settings_screen.dart').readAsStringSync();

    const gate = 'if (AppConfig.isDev || AppConfig.isTester)';
    expect(
      source.contains(gate),
      isTrue,
      reason: '言語切替の導線が製品ビルドに出てしまう',
    );
    // 切替の入口はゲートの内側にしか無いこと。
    final gateIndex = source.indexOf(gate);
    final pickerCall = source.indexOf('_showLanguagePicker(');
    expect(pickerCall, greaterThan(gateIndex),
        reason: 'ゲートの外から _showLanguagePicker を呼んでいる');
    // ゲートは1つだけ。増やすと入口がどこにあるか追えなくなる。
    expect(
      gate.allMatches(source).length,
      1,
      reason: '言語切替のゲートが複数ある',
    );
  });
}
