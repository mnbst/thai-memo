/// 言語切替が製品ビルドから使えることを固定する。
///
/// 以前は導線を dev / tester だけに開いていた（切り替えても生成済みの履歴は
/// 書き換わらず、1つの履歴に日英が混在するため）。ただし言語は初回起動で
/// ストア地域から1回決めて保存し以後は再評価しないので、閉じたままだと
/// ストア地域と使用言語が違うユーザーに戻す手段が無い。害の大きさを比べて
/// 開く判断をした。履歴が混在する点はダイアログの注記で伝える。
/// ゲートを戻す変更をここで止める。
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

  test('設定画面の言語切替はビルド種別でゲートされていない', () {
    final source =
        File('lib/presentation/screens/settings_screen.dart').readAsStringSync();

    final pickerCall = source.indexOf('_showLanguagePicker(ref.read(');
    expect(pickerCall, greaterThan(-1), reason: '言語切替の入口が無い');

    // 入口の直前にビルド種別のゲートが無いこと。ListTile を条件で包むと
    // 行が近いので、手前 400 文字だけ見れば足りる。
    final before =
        source.substring((pickerCall - 400).clamp(0, pickerCall), pickerCall);
    expect(
      before.contains('AppConfig.isDev') || before.contains('AppConfig.isTester'),
      isFalse,
      reason: '言語切替が製品ビルドで使えなくなっている',
    );
  });

  test('切替ダイアログは履歴が書き換わらないことを注記する', () {
    final source =
        File('lib/presentation/screens/settings_screen.dart').readAsStringSync();

    expect(
      source.contains('l10n.settingsLanguageNote'),
      isTrue,
      reason: '履歴に日英が混在する点を伝える注記が消えている',
    );
  });
}
