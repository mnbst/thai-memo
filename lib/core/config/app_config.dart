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
  static const int databaseVersion = 12;

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

  /// 毎日例文のプッシュ通知を受け取るか（サーバー側 daily_reminder_enabled のミラー）
  static const String prefKeyDailyReminderEnabled = 'daily_reminder_enabled';
  static const String prefKeyFirstSummaryQuizCompleted =
      'first_summary_quiz_completed';

  /// 例文カード（詳細を開く）のコーチマーク表示済みフラグ。
  /// 初回ガイドの1段目で、これを見せた後に [prefKeySentenceCoachShown] へ進む。
  static const String prefKeyDetailCoachShown = 'detail_coach_shown';

  /// 「確認クイズへ」ボタンのコーチマーク表示済みフラグ
  static const String prefKeySentenceCoachShown = 'sentence_coach_shown';

  /// 出題中の「例文を確認」導線のコーチマーク表示済みフラグ
  static const String prefKeyQuizReviewCoachShown = 'quiz_review_coach_shown';

  /// まとめクイズ誘導ボタンのコーチマーク表示済みフラグ
  static const String prefKeyQuizButtonCoachShown = 'quiz_button_coach_shown';

  /// 「次のテーマ」コーチマークの表示済みフラグ
  static const String prefKeyNextTopicCoachShown = 'next_topic_coach_shown';

  /// コーチマーク移行処理の実施済みフラグ（既存ユーザーには表示しない）
  static const String prefKeyCoachMarksMigrated = 'coach_marks_migrated';

  /// サインイン促進バナーを閉じた日時（epoch ms）
  static const String prefKeySignInReminderDismissedAt =
      'sign_in_reminder_dismissed_at';

  /// 毎日例文通知のコーチングダイアログ表示済みフラグ（設定画面の初回表示時に出す）
  static const String prefKeyNotificationCoachShown =
      'notification_coach_shown';

  /// 例文タブのプレミアム訴求バナーを閉じた日時（epoch ms）
  static const String prefKeyPremiumHintDismissedAt =
      'premium_hint_dismissed_at';

  /// アプリの言語（UI文言と訳文の両方）。初回起動時にストア地域から決め、
  /// 以降はこの値が真実（設定画面から変更可能）。
  static const String prefKeyAppLanguage = 'app_language';

  /// プレミアム体験の終了を通知済みか（起動時の案内を一度だけ出すため）
  static const String prefKeyPremiumTrialEndedNotified =
      'premium_trial_ended_notified';

  /// quiz_offer(assigned)を送信済みの実験群。画面再生成での重複を防ぐ。
  static const String prefKeyQuizOfferAssignmentLoggedV1 =
      'quiz_offer_assignment_logged_v1';
}
