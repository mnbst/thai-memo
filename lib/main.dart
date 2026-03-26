import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'app.dart';
import 'core/config/app_config.dart';
import 'firebase_options_dev.dart';
import 'firebase_options_prod.dart';
import 'firebase_options_tester.dart';
import 'presentation/providers/subscription_provider.dart';
import 'services/admob_service.dart';

void main() async {
  // Ensure Flutter binding is initialized
  WidgetsFlutterBinding.ensureInitialized();

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

  // Initialize Google Sign-In
  await GoogleSignIn.instance.initialize(
    serverClientId:
        '147810088545-4921rt150m9jtjate82nbol5q8hgoj3l.apps.googleusercontent.com',
  );

  // Initialize AdMob
  await AdMobService.instance.initialize();

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
}
