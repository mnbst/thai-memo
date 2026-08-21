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

  /// 「今日の学習単語」のコーチマーク表示済みフラグ。
  /// クイズを一度見てから例文へ戻った回に、出題される語を結び付けて教える。
  static const String prefKeyTargetWordsCoachShown = 'target_words_coach_shown';

  /// 出題中の「例文を確認」導線のコーチマーク表示済みフラグ
  static const String prefKeyQuizReviewCoachShown = 'quiz_review_coach_shown';

  /// まとめクイズ誘導ボタンのコーチマーク表示済みフラグ
  static const String prefKeyQuizButtonCoachShown = 'quiz_button_coach_shown';

  /// 「次のテーマ」コーチマークの表示済みフラグ
  static const String prefKeyNextTopicCoachShown = 'next_topic_coach_shown';

  /// 詳細画面の初回ガイドの進捗（0=例文カード / 1=発音練習 / 2=単語の分解 /
  /// 3=文脈・使い方 / 4=戻る / 5=完了）。途中で画面を離れても残りから再開する
  /// ため、真偽値ではなく段で持つ。
  ///
  /// 段を増やしたときは新しいキーにする。旧キーの番号は1つ手前を指すので、
  /// そのまま使うと同じ案内を二度読ませる（detail_screen で読み替える）。
  static const String prefKeyDetailTourStep = 'detail_tour_step_v2';

  /// 例文カードの案内を足す前の進捗キー（読み替え用）。
  static const String prefKeyDetailTourStepV1 = 'detail_tour_step';

  /// 発音練習セクションのコーチマーク表示済みフラグ（旧版の名残）

  static const String prefKeyPronunciationCoachShown =
      'pronunciation_coach_shown';

  /// コーチマーク移行処理の実施済みフラグ（既存ユーザーには表示しない）
  static const String prefKeyCoachMarksMigrated = 'coach_marks_migrated';

  /// サインイン促進バナーを閉じた日時（epoch ms）
  static const String prefKeySignInReminderDismissedAt =
      'sign_in_reminder_dismissed_at';

  /// 毎日例文通知のコーチングダイアログ表示済みフラグ（設定画面の初回表示時に出す）
  static const String prefKeyNotificationCoachShown =
      'notification_coach_shown';

  /// 暫定許可（iOS の provisional authorization）を要求済みかどうか。
  ///
  /// ダイアログが出ない代わりに一度しか意味を持たない要求なので、成否に
  /// かかわらず一度で打ち切る。再登録は起動時の同期が引き受ける。
  static const String prefKeyProvisionalPushRequested =
      'provisional_push_requested';

  /// 例文タブのプレミアム訴求バナーを閉じた日時（epoch ms）
  static const String prefKeyPremiumHintDismissedAt =
      'premium_hint_dismissed_at';

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
