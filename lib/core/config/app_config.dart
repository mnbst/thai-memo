/// Application-wide configuration settings
class AppConfig {
  AppConfig._();

  /// App name
  static const String appName = 'Thai Memo';

  /// App version
  static const String appVersion = '1.0.0';

  /// Database configuration
  static const String databaseName = 'thai_memo.db';
  static const int databaseVersion = 4;

  /// Background task configuration
  static const Duration backgroundTaskFrequency = Duration(hours: 24);

  /// UI configuration
  static const double defaultPadding = 16.0;
  static const double cardBorderRadius = 12.0;

  /// Secure storage keys
  static const String secureStorageLastGeneration = 'last_generation_timestamp';

  /// Shared preferences keys
  static const String prefKeyFirstLaunch = 'is_first_launch';
  static const String prefKeyNotificationsEnabled = 'notifications_enabled';
  static const String prefKeyThemeMode = 'theme_mode';
  static const String prefKeyPreferredGenerationTime =
      'preferred_generation_time';
}
