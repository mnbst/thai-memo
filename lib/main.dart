import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'services/background_service.dart';
import 'services/notification_service.dart';

void main() async {
  // Ensure Flutter binding is initialized
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize services (only on mobile platforms)
  if (!kIsWeb) {
    await _initializeServices();
  } else {
    debugPrint('Running on web - skipping mobile-only services');
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
    debugPrint('Notification service initialized');

    // Initialize background service
    await BackgroundService.instance.initialize();
    debugPrint('Background service initialized');

    // Note: Background task will be registered when user sets API key
    // in settings screen
  } catch (e) {
    debugPrint('Failed to initialize services: $e');
  }
}
