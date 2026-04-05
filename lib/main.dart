import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/config/app_config.dart';
import 'firebase_options_dev.dart';
import 'firebase_options_prod.dart';
import 'firebase_options_tester.dart';

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

  // Run app with Riverpod
  runApp(const ProviderScope(child: ThaiMemoApp()));
}
