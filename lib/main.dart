import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app.dart';
import 'core/config/app_config.dart';
import 'firebase_options_dev.dart';
import 'firebase_options_prod.dart';
import 'firebase_options_tester.dart';

/// App Check デバッグトークン。dev/tester の Firebase に登録済みの値を
/// `--dart-define-from-file=dart_defines.json`（git 管理外）で渡す。
/// 未指定なら null を渡し、SDK 既定のトークン探索に任せる。
const String? _appCheckDebugToken =
    String.fromEnvironment('APP_CHECK_DEBUG_TOKEN') == ''
        ? null
        : String.fromEnvironment('APP_CHECK_DEBUG_TOKEN');

void main() async {
  // Ensure Flutter binding is initialized
  WidgetsFlutterBinding.ensureInitialized();

  // フォントは google_fonts/ に同梱済み。実行時に fonts.gstatic.com へ
  // 取りに行かせない（オフライン・低速回線でのフォールバックを防ぐ）。
  GoogleFonts.config.allowRuntimeFetching = false;
  LicenseRegistry.addLicense(() async* {
    final license = await rootBundle.loadString('google_fonts/OFL.txt');
    yield LicenseEntryWithLineBreaks(const ['google_fonts'], license);
  });

  // Flutter は支援技術が接続されるまでセマンティクスツリーを構築しないため、
  // Maestro などアクセシビリティ経由でUIを読む自動化ツールからは中身が空に見える。
  // debug ビルドでのみ常時有効にする（release は従来どおり必要時のみ構築）。
  if (kDebugMode) {
    SemanticsBinding.instance.ensureSemantics();
  }

  // Initialize Firebase（環境に応じて設定を切替）
  final firebaseOptions = AppConfig.isProd
      ? ProdFirebaseOptions.currentPlatform
      : AppConfig.isTester
          ? TesterFirebaseOptions.currentPlatform
          : DefaultFirebaseOptions.currentPlatform;
  try {
    await Firebase.initializeApp(options: firebaseOptions);
  } on FirebaseException catch (e) {
    if (e.code != 'duplicate-app') rethrow;
  }

  // App Check（未 activate だとダミートークンが送られサーバ側の検証が失敗する）。
  // シミュレータは App Attest を使えないため debug provider を使う。SDK は
  // デバッグトークンをプロセス環境変数からしか読まず flutter run では渡せないので、
  // dart-define で受け取って明示的に渡す（未指定だと SDK がランダム UUID を生成し、
  // 未登録なのでトークン交換に失敗する）。
  // 取得に失敗してもアプリは継続させる（現状 enforcement は UNENFORCED）。
  try {
    await FirebaseAppCheck.instance.activate(
      providerApple: kDebugMode
          ? const AppleDebugProvider(debugToken: _appCheckDebugToken)
          : const AppleAppAttestProvider(),
      providerAndroid: kDebugMode
          ? const AndroidDebugProvider(debugToken: _appCheckDebugToken)
          : const AndroidPlayIntegrityProvider(),
    );
  } catch (e) {
    debugPrint('App Check activation failed: $e');
  }

  // Run app with Riverpod
  runApp(const ProviderScope(child: ThaiMemoApp()));
}
