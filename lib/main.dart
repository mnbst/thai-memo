import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/config/app_config.dart';
import 'firebase_options_dev.dart';
import 'firebase_options_prod.dart';
import 'firebase_options_tester.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'presentation/providers/subscription_provider.dart';
import 'services/admob_service.dart';
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

  // バックグラウンドFCMハンドラ登録（Firebase初期化直後に設定）
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  // Initialize AdMob
  await AdMobService.instance.initialize();

  // Initialize FCM (auth is now handled by login screen)
  try {
    if (FirebaseAuthService.instance.isAuthenticated) {
      await FcmService.instance.initialize();
    }
  } catch (_) {}

  // ProviderContainerを共有してFCMハンドラからもproviderにアクセス可能にする
  final container = ProviderContainer();

  // PurchaseServiceを初期化し、SubscriptionControllerに接続
  final purchaseService = container.read(purchaseServiceProvider);
  await purchaseService.initialize();
  container
      .read(subscriptionControllerProvider.notifier)
      .setPurchaseService(purchaseService);

  // Run app with Riverpod
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const ThaiMemoApp(),
    ),
  );

  // navigatorKeyが有効になった後に通知ハンドラをセットアップ
  WidgetsBinding.instance.addPostFrameCallback((_) {
    FcmService.instance.setupNotificationHandlers();
  });
}
