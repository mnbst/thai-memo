import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';

import '../core/config/app_config.dart';
import '../data/datasources/local/database_helper.dart';
import '../data/datasources/local/secure_storage_service.dart';
import '../data/datasources/remote/openai_api_service.dart';
import '../data/repositories/sentence_repository.dart';
import '../domain/usecases/generate_sentence_usecase.dart';
import 'notification_service.dart';

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
      debugPrint('Background service initialized');
      return true;
    } catch (e) {
      debugPrint('Failed to initialize background service: $e');
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

      debugPrint('Daily task registered');
    } catch (e) {
      debugPrint('Failed to register daily task: $e');
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

      debugPrint('Immediate task registered');
    } catch (e) {
      debugPrint('Failed to register immediate task: $e');
      rethrow;
    }
  }

  /// Cancel all background tasks
  Future<void> cancelAllTasks() async {
    try {
      await Workmanager().cancelAll();
      debugPrint('All background tasks cancelled');
    } catch (e) {
      debugPrint('Failed to cancel tasks: $e');
    }
  }

  /// Cancel specific task
  Future<void> cancelTask(String taskName) async {
    try {
      await Workmanager().cancelByUniqueName(taskName);
      debugPrint('Task cancelled: $taskName');
    } catch (e) {
      debugPrint('Failed to cancel task: $e');
    }
  }
}

/// Background callback dispatcher
///
/// This function MUST be a top-level function
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    debugPrint('Background task started: $task');

    try {
      // Execute the sentence generation
      await _executeSentenceGeneration();

      debugPrint('Background task completed successfully');
      return Future.value(true);
    } catch (e) {
      debugPrint('Background task failed: $e');

      // Show error notification
      try {
        await NotificationService.instance.initialize();
        await NotificationService.instance.showErrorNotification(
          '例文の自動生成に失敗しました',
        );
      } catch (notifError) {
        debugPrint('Failed to show error notification: $notifError');
      }

      return Future.value(false);
    }
  });
}

/// Execute sentence generation in background
///
/// This is the main logic executed by the background task
Future<void> _executeSentenceGeneration() async {
  debugPrint('Executing sentence generation...');

  // Initialize services
  final secureStorage = SecureStorageService.instance;
  final databaseHelper = DatabaseHelper.instance;
  final apiService = OpenAiApiService();

  // Check if API key is configured
  final hasApiKey = await secureStorage.hasApiKey();
  if (!hasApiKey) {
    debugPrint('API key not configured, skipping generation');
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
      debugPrint(
        'Last generation was ${timeSinceLastGeneration.inHours} hours ago, skipping',
      );
      return;
    }
  }

  // Create repository
  final repository = SentenceRepository(
    databaseHelper: databaseHelper,
    apiService: apiService,
    secureStorage: secureStorage,
  );

  // Create use case
  final generateUseCase = GenerateSentenceUseCase(repository);

  // Generate and save sentence
  final sentence = await generateUseCase.execute();
  debugPrint('Sentence generated: ${sentence.id}');

  // Update last generation timestamp
  await secureStorage.saveLastGenerationTimestamp(DateTime.now());

  // Show notification
  await NotificationService.instance.initialize();
  await NotificationService.instance.showNewSentenceNotification(sentence);

  debugPrint('Notification shown');
}
