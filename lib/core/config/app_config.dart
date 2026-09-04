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

  /// Database configuration
  static const String databaseName = 'thai_memo.db';
  static const int databaseVersion = 12;

  /// Background task configuration
  static const Duration backgroundTaskFrequency = Duration(hours: 24);

  /// UI configuration
  static const double defaultPadding = 16.0;
  static const double cardBorderRadius = 16.0;

  /// 例文カードなど、画面の主役になる面の角丸。
  static const double heroBorderRadius = 20.0;

  /// ボタン・入力欄の角丸。
  static const double buttonBorderRadius = 14.0;

  /// タップ領域の最小辺。
  static const double minTapTarget = 44.0;

  /// 画面端の余白。
  static const double screenPadding = 20.0;

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

  /// 既存ユーザー向け移行処理の実施済みフラグ（初回導線を出し直さない）。
  static const String prefKeyCoachMarksMigrated = 'coach_marks_migrated';

  /// サインイン促進バナーを閉じた日時（epoch ms）
  static const String prefKeySignInReminderDismissedAt =
      'sign_in_reminder_dismissed_at';

  /// 毎日例文通知のコーチングダイアログ表示済みフラグ（設定画面の初回表示時に出す）
  static const String prefKeyNotificationCoachShown =
      'notification_coach_shown';

  /// アプリの言語（UI文言と訳文の両方）。初回起動時にストア地域から決め、
  /// 以降はこの値が真実（設定画面から変更可能）。
  static const String prefKeyAppLanguage = 'app_language';

  /// プレミアム体験の終了を通知済みか（起動時の案内を一度だけ出すため）
  static const String prefKeyPremiumTrialEndedNotified =
      'premium_trial_ended_notified';

  /// プレミアム体験の開放を通知済みか（後から配った既存ユーザー向けの案内）
  static const String prefKeyPremiumTrialStartedNotified =
      'premium_trial_started_notified';

  /// ヒアリングの回答を保存するキーの接頭辞（`interview_level` など）。
  /// 回答は例文生成には効かせず、案内の出し分けと分析にだけ使う。
  static const String prefKeyInterviewPrefix = 'interview_';

  /// ヒアリングの設問キー。prefs・Firestore・GA4 でこの並びを共有する。
  /// 設問を足したらここにも足す（[interviewQuestionKeys] にない回答は
  /// users doc へ上がらない）。
  static const List<String> interviewQuestionKeys = [
    'level',
    'goal',
    'time',
    'struggle',
  ];

  /// ヒアリングを通過したか。全問スキップでも立てる。
  /// 「まだ来ていない人」と「答えずに抜けた人」を分けるために要る。
  static const String prefKeyInterviewCompleted = 'interview_completed';

  /// ヒアリングの回答を users doc へ書けたか。初回起動時に圏外だと書けないので、
  /// 立つまで起動のたびに送り直す。
  static const String prefKeyInterviewSynced = 'interview_synced';

  /// quiz_offer(assigned)を送信済みの実験群。画面再生成での重複を防ぐ。
  static const String prefKeyQuizOfferAssignmentLoggedV1 =
      'quiz_offer_assignment_logged_v1';
}
