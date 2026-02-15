import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'firebase_options.dart';
import 'services/firebase_auth_service.dart';

void main() async {
  // Ensure Flutter binding is initialized
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Authenticate user anonymously on startup
  try {
    await FirebaseAuthService.instance.ensureAuthenticated();
  } catch (e) {
    // Continue anyway - will retry on first generation attempt
  }

  // Run app with Riverpod
  runApp(
    const ProviderScope(
      child: ThaiMemoApp(),
    ),
  );
}
