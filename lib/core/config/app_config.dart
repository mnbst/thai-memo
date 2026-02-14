/// Application-wide configuration settings
class AppConfig {
  AppConfig._();

  /// App name
  static const String appName = 'Thai Memo';

  /// App version
  static const String appVersion = '1.0.0';

  /// Database configuration
  static const String databaseName = 'thai_memo.db';
  static const int databaseVersion = 1;

  /// API configuration
  static const String geminiModel = 'gemini-2.5-flash';
  static const int apiMaxTokens = 6144;
  static const double apiTemperature = 0.8;
  static const int apiTimeoutSeconds = 30;

  /// Background task configuration
  static const String backgroundTaskName = 'thaiMemoDaily';
  static const Duration backgroundTaskFrequency = Duration(hours: 24);

  /// Notification configuration
  static const String notificationChannelId = 'thai_memo_daily';
  static const String notificationChannelName = 'Thai Daily Sentences';
  static const String notificationChannelDescription =
      'Notifications for new Thai sentences';
  static const int newSentenceNotificationId = 1;
  static const int errorNotificationId = 2;

  /// UI configuration
  static const Duration animationDuration = Duration(milliseconds: 300);
  static const double defaultPadding = 16.0;
  static const double cardBorderRadius = 12.0;

  /// Secure storage keys
  static const String secureStorageApiKey = 'gemini_api_key';
  static const String secureStorageLastGeneration = 'last_generation_timestamp';

  /// Shared preferences keys
  static const String prefKeyFirstLaunch = 'is_first_launch';
  static const String prefKeyNotificationsEnabled = 'notifications_enabled';
  static const String prefKeyThemeMode = 'theme_mode';
  static const String prefKeyPreferredGenerationTime =
      'preferred_generation_time';
}
