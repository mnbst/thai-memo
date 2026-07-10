/// SettingsController.migrateExistingUserFlags のテスト
///
/// コーチマーク・オンボーディング導入前からの既存ユーザーに、アップデート後
/// これらが再表示されないようにする一度きりの移行処理を検証する。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thai_memo/core/config/app_config.dart';
import 'package:thai_memo/presentation/providers/settings_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<SharedPreferences> prefsWith(Map<String, Object> values) async {
    SharedPreferences.setMockInitialValues(values);
    return SharedPreferences.getInstance();
  }

  Future<bool> Function() sentences(bool exists) => () async => exists;

  test('既存ユーザー（DBに例文あり・フラグ未登録）は全フラグが立つ', () async {
    final prefs = await prefsWith({});

    await SettingsController.migrateExistingUserFlags(prefs, sentences(true));

    expect(prefs.getBool(AppConfig.prefKeyFirstLaunch), isFalse);
    expect(prefs.getBool(AppConfig.prefKeySentenceCoachShown), isTrue);
    expect(prefs.getBool(AppConfig.prefKeyQuizButtonCoachShown), isTrue);
    expect(prefs.getBool(AppConfig.prefKeyNextTopicCoachShown), isTrue);
    expect(prefs.getBool(AppConfig.prefKeyCoachMarksMigrated), isTrue);
  });

  test('既存ユーザー（is_first_launch=false 済み）は例文が無くても既存扱い', () async {
    final prefs = await prefsWith({AppConfig.prefKeyFirstLaunch: false});

    await SettingsController.migrateExistingUserFlags(prefs, sentences(false));

    expect(prefs.getBool(AppConfig.prefKeyFirstLaunch), isFalse);
    expect(prefs.getBool(AppConfig.prefKeySentenceCoachShown), isTrue);
    expect(prefs.getBool(AppConfig.prefKeyCoachMarksMigrated), isTrue);
  });

  test('新規インストール（例文なし・フラグ未登録）はフラグを立てず移行のみ記録', () async {
    final prefs = await prefsWith({});

    await SettingsController.migrateExistingUserFlags(prefs, sentences(false));

    // is_first_launch は未登録のまま（＝true 扱い）でオンボ・コーチが出せる
    expect(prefs.getBool(AppConfig.prefKeyFirstLaunch), isNull);
    expect(prefs.getBool(AppConfig.prefKeySentenceCoachShown), isNull);
    expect(prefs.getBool(AppConfig.prefKeyQuizButtonCoachShown), isNull);
    expect(prefs.getBool(AppConfig.prefKeyNextTopicCoachShown), isNull);
    // 移行自体は実施済みとして記録し、二度と走らないようにする
    expect(prefs.getBool(AppConfig.prefKeyCoachMarksMigrated), isTrue);
  });

  test('移行済み（coach_marks_migrated=true）なら何もしない（冪等）', () async {
    final prefs = await prefsWith({
      AppConfig.prefKeyCoachMarksMigrated: true,
      AppConfig.prefKeyFirstLaunch: true,
    });
    var called = false;

    await SettingsController.migrateExistingUserFlags(prefs, () async {
      called = true;
      return true;
    });

    // 既存の is_first_launch=true を上書きせず、DB照会も行わない
    expect(called, isFalse);
    expect(prefs.getBool(AppConfig.prefKeyFirstLaunch), isTrue);
    expect(prefs.getBool(AppConfig.prefKeySentenceCoachShown), isNull);
  });
}
