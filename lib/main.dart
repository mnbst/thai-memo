import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'services/background_service.dart';
import 'services/firebase_auth_service.dart';
import 'services/notification_service.dart';

void main() async {
  // Ensure Flutter binding is initialized
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase
  await Firebase.initializeApp();

  // Authenticate user anonymously on startup
  try {
    await FirebaseAuthService.instance.ensureAuthenticated();
  } catch (e) {
    // Continue anyway - will retry on first generation attempt
  }

  // Initialize services (only on mobile platforms)
  if (!kIsWeb) {
    await _initializeServices();
  }

  // Run app with Riverpod
  runApp(
    const ProviderScope(
      child: ThaiMemoApp(),
    ),
  );
}

/// Initialize all services
Future<void> _initializeServices() async {
  try {
    // Initialize notification service
    await NotificationService.instance.initialize();

    // Initialize background service
    await BackgroundService.instance.initialize();

    // Register background task for daily sentence generation
    await BackgroundService.instance.registerDailyTask();
  } catch (e) {
    // Silently ignore initialization errors
  }
}
