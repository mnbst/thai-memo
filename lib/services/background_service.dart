import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../core/config/app_config.dart';
import '../data/datasources/local/database_helper.dart';
import '../data/datasources/local/secure_storage_service.dart';
import '../data/datasources/backend_api_service.dart';
import '../data/sentence_repository.dart';
import '../domain/generate_sentence_usecase.dart';
import 'firebase_auth_service.dart';

/// Background service for periodic sentence generation
class BackgroundService {
  static final BackgroundService instance = BackgroundService._internal();

  factory BackgroundService() => instance;

  BackgroundService._internal();

  bool _initialized = false;

  /// Initialize background service
  ///
  /// Must be called on app startup
  Future<bool> initialize() async {
    if (_initialized) return true;

    try {
      await Workmanager().initialize(
        callbackDispatcher,
        isInDebugMode: kDebugMode,
      );

      _initialized = true;
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Register periodic sentence generation task
  ///
  /// [initialDelayMinutes] is the delay before first execution (default: 1 minute)
  Future<void> registerDailyTask({int initialDelayMinutes = 1}) async {
    if (!_initialized) {
      await initialize();
    }

    try {
      await Workmanager().registerPeriodicTask(
        AppConfig.backgroundTaskName,
        AppConfig.backgroundTaskName,
        frequency: AppConfig.backgroundTaskFrequency,
        initialDelay: Duration(minutes: initialDelayMinutes),
        constraints: Constraints(
          networkType: NetworkType.connected,
        ),
        existingWorkPolicy: ExistingWorkPolicy.keep,
      );
    } catch (e) {
      rethrow;
    }
  }

  /// Register one-time immediate task for testing
  Future<void> registerImmediateTask() async {
    if (!_initialized) {
      await initialize();
    }

    try {
      await Workmanager().registerOneOffTask(
        '${AppConfig.backgroundTaskName}_immediate',
        AppConfig.backgroundTaskName,
        initialDelay: const Duration(seconds: 5),
        constraints: Constraints(
          networkType: NetworkType.connected,
        ),
      );
    } catch (e) {
      rethrow;
    }
  }

  /// Cancel all background tasks
  Future<void> cancelAllTasks() async {
    try {
      await Workmanager().cancelAll();
    } catch (e) {
      // Silently ignore errors
    }
  }

  /// Cancel specific task
  Future<void> cancelTask(String taskName) async {
    try {
      await Workmanager().cancelByUniqueName(taskName);
    } catch (e) {
      // Silently ignore errors
    }
  }
}

/// Background callback dispatcher
///
/// This function MUST be a top-level function
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      // Execute the sentence generation
      await _executeSentenceGeneration();

      return Future.value(true);
    } catch (e) {
      return Future.value(false);
    }
  });
}

/// Execute sentence generation in background
///
/// This is the main logic executed by the background task
Future<void> _executeSentenceGeneration() async {
  // Initialize services
  final secureStorage = SecureStorageService.instance;
  final databaseHelper = DatabaseHelper.instance;
  final apiService = BackendApiService();
  final authService = FirebaseAuthService.instance;

  // Ensure user is authenticated
  try {
    await authService.ensureAuthenticated();
  } catch (e) {
    return;
  }

  // Check if generation is due (prevent duplicate generations)
  final lastGenerationTimestamp =
      await secureStorage.getLastGenerationTimestamp();

  if (lastGenerationTimestamp != null) {
    final now = DateTime.now();
    final timeSinceLastGeneration = now.difference(lastGenerationTimestamp);

    // Skip if last generation was less than 23 hours ago
    if (timeSinceLastGeneration.inHours < 23) {
      return;
    }
  }

  // Create repository
  final repository = SentenceRepository(
    databaseHelper: databaseHelper,
    apiService: apiService,
    secureStorage: secureStorage,
    authService: authService,
  );

  // Load generation params from SharedPreferences
  final prefs = await SharedPreferences.getInstance();
  const paramKeys = [
    'style', 'topic', 'politeness', 'grammarFocus',
    'vocabLevel', 'sentenceLength', 'emotion', 'learningPurpose', 'toneDensity',
  ];
  final generationParams = <String, String?>{};
  for (final key in paramKeys) {
    generationParams[key] = prefs.getString('pref_$key');
  }

  // Create use case
  final generateUseCase = GenerateSentenceUseCase(repository);

  // Generate and save sentence
  await generateUseCase.execute(generationParams: generationParams);

  // Update last generation timestamp
  await secureStorage.saveLastGenerationTimestamp(DateTime.now());
}
