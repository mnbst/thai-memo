/// Application-wide configuration settings
class AppConfig {
  AppConfig._();

  /// 環境判定（--dart-define=ENV=prod で本番）
  static const String env = String.fromEnvironment('ENV', defaultValue: 'dev');
  static bool get isProd => env == 'prod';
  static bool get isTester => env == 'tester';
  static bool get isDev => env != 'prod' && env != 'tester';

  /// App name
  static const String appName = 'まいにちタイ語';

  /// App version
  static const String appVersion = '1.2.1';

  /// Database configuration
  static const String databaseName = 'thai_memo.db';
  static const int databaseVersion = 11;

  /// Background task configuration
  static const Duration backgroundTaskFrequency = Duration(hours: 24);

  /// UI configuration
  static const double defaultPadding = 16.0;
  static const double cardBorderRadius = 12.0;

  /// Secure storage keys
  static const String secureStorageLastGeneration = 'last_generation_timestamp';

  /// Legal URLs
  static const String privacyPolicyUrl =
      'https://thai-memo-prod.web.app/privacy-policy.html';
  static const String termsOfServiceUrl =
      'https://thai-memo-prod.web.app/terms.html';

  /// Shared preferences keys
  static const String prefKeyFirstLaunch = 'is_first_launch';
  static const String prefKeyThemeMode = 'theme_mode';
  static const String prefKeyPreferredGenerationTime =
      'preferred_generation_time';
  static const String prefKeyFirstSummaryQuizCompleted =
      'first_summary_quiz_completed';
}
