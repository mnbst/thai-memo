import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../core/config/app_config.dart';
import '../data/models/thai_sentence.dart';

/// Service for managing local notifications
class NotificationService {
  static final NotificationService instance = NotificationService._internal();

  factory NotificationService() => instance;

  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  /// Initialize notification service
  ///
  /// Must be called before showing notifications
  /// Returns true if initialization succeeded
  Future<bool> initialize() async {
    if (_initialized) return true;

    try {
      // Android initialization settings
      const androidSettings = AndroidInitializationSettings(
        '@mipmap/ic_launcher',
      );

      // iOS initialization settings
      const iosSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );

      const initSettings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );

      // Initialize with callback for notification taps
      final result = await _notifications.initialize(
        initSettings,
        onDidReceiveNotificationResponse: _onNotificationTapped,
      );

      _initialized = result ?? false;

      if (_initialized) {
        // Create notification channel for Android
        await _createNotificationChannel();
      }

      return _initialized;
    } catch (e) {
      return false;
    }
  }

  /// Create notification channel for Android
  Future<void> _createNotificationChannel() async {
    const androidChannel = AndroidNotificationChannel(
      AppConfig.notificationChannelId,
      AppConfig.notificationChannelName,
      description: AppConfig.notificationChannelDescription,
      importance: Importance.high,
      enableVibration: true,
      playSound: true,
    );

    await _notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(androidChannel);
  }

  /// Handle notification tap
  void _onNotificationTapped(NotificationResponse response) {
    // TODO: Navigate to the sentence detail screen
    // This will be implemented when we create the navigation system
  }

  /// Request notification permissions (iOS)
  Future<bool> requestPermissions() async {
    if (!_initialized) {
      await initialize();
    }

    final iosImplementation =
        _notifications.resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>();

    final result = await iosImplementation?.requestPermissions(
      alert: true,
      badge: true,
      sound: true,
    );

    return result ?? false;
  }

  /// Show notification for new sentence generation
  ///
  /// [sentence] is the newly generated sentence
  Future<void> showNewSentenceNotification(ThaiSentence sentence) async {
    if (!_initialized) {
      final success = await initialize();
      if (!success) {
        return;
      }
    }

    try {
      // Truncate Thai text if too long
      final thaiText = sentence.thaiText.length > 50
          ? '${sentence.thaiText.substring(0, 50)}...'
          : sentence.thaiText;

      // Truncate Japanese translation if too long
      final japaneseText = sentence.japaneseTranslation.length > 100
          ? '${sentence.japaneseTranslation.substring(0, 100)}...'
          : sentence.japaneseTranslation;

      const androidDetails = AndroidNotificationDetails(
        AppConfig.notificationChannelId,
        AppConfig.notificationChannelName,
        channelDescription: AppConfig.notificationChannelDescription,
        importance: Importance.high,
        priority: Priority.high,
        showWhen: true,
        enableVibration: true,
        playSound: true,
      );

      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      const notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await _notifications.show(
        AppConfig.newSentenceNotificationId,
        '今日のタイ語例文が届きました！',
        '$thaiText\n$japaneseText',
        notificationDetails,
        payload: sentence.id,
      );
    } catch (e) {
      // Silently ignore notification errors
    }
  }

  /// Show error notification
  ///
  /// [message] is the error message to display
  Future<void> showErrorNotification(String message) async {
    if (!_initialized) {
      final success = await initialize();
      if (!success) return;
    }

    try {
      const androidDetails = AndroidNotificationDetails(
        AppConfig.notificationChannelId,
        AppConfig.notificationChannelName,
        channelDescription: AppConfig.notificationChannelDescription,
        importance: Importance.high,
        priority: Priority.high,
      );

      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      const notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await _notifications.show(
        AppConfig.errorNotificationId,
        'エラーが発生しました',
        message,
        notificationDetails,
      );
    } catch (e) {
      // Silently ignore notification errors
    }
  }

  /// Cancel all notifications
  Future<void> cancelAll() async {
    await _notifications.cancelAll();
  }

  /// Cancel specific notification
  Future<void> cancel(int id) async {
    await _notifications.cancel(id);
  }

  /// Check if notifications are enabled
  Future<bool> areNotificationsEnabled() async {
    if (!_initialized) {
      await initialize();
    }

    // Check Android
    final androidImplementation =
        _notifications.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    final androidEnabled =
        await androidImplementation?.areNotificationsEnabled();

    if (androidEnabled != null) {
      return androidEnabled;
    }

    // For iOS, we assume notifications are enabled if initialization succeeded
    return _initialized;
  }
}
