import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/config/app_config.dart';
import 'firebase_options_dev.dart';
import 'firebase_options_prod.dart';
import 'firebase_options_tester.dart';
import 'presentation/providers/review_provider.dart';
import 'services/fcm_service.dart';
import 'services/firebase_auth_service.dart';

void main() async {
  // Ensure Flutter binding is initialized
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase（環境に応じて設定を切替）
  final firebaseOptions = AppConfig.isProd
      ? ProdFirebaseOptions.currentPlatform
      : AppConfig.isTester
          ? TesterFirebaseOptions.currentPlatform
          : DefaultFirebaseOptions.currentPlatform;
  await Firebase.initializeApp(options: firebaseOptions);

  // Authenticate user anonymously on startup
  try {
    await FirebaseAuthService.instance.ensureAuthenticated();
    // Initialize FCM after authentication
    await FcmService.instance.initialize();
  } catch (e) {
    // Continue anyway - will retry on first generation attempt
  }

  // ProviderContainerを共有してFCMハンドラからもproviderにアクセス可能にする
  final container = ProviderContainer();

  // Run app with Riverpod
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const ThaiMemoApp(),
    ),
  );

  // navigatorKeyが有効になった後に通知ハンドラをセットアップ
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final reviewNotifier = container.read(reviewProvider.notifier);
    FcmService.instance.setupNotificationHandlers(reviewNotifier);
  });
}
