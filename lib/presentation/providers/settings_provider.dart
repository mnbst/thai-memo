import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/config/app_config.dart';
import '../../core/l10n/app_language.dart';
import '../../data/datasources/local/database_helper.dart';
import '../../services/analytics_service.dart';
import '../../services/push_notification_service.dart';
import '../../services/storefront_service.dart';
import 'analytics_provider.dart';

// ==================== Font Family ====================

enum ThaiFont { sarabun, krub, notoSansThai, mitr }

extension ThaiFontExtension on ThaiFont {
  String get displayName {
    switch (this) {
      case ThaiFont.notoSansThai:
        return 'Noto Sans Thai';
      case ThaiFont.mitr:
        return 'Mitr';
      case ThaiFont.sarabun:
        return 'Sarabun';
      case ThaiFont.krub:
        return 'Krub';
    }
  }

  String get prefValue => name;

  static ThaiFont fromPrefValue(String value) {
    return ThaiFont.values.firstWhere(
      (e) => e.name == value,
      orElse: () => ThaiFont.sarabun,
    );
  }
}

// ==================== Settings State ====================

/// Settings state class
class SettingsState {
  final bool isFirstLaunch;
  final ThemeMode themeMode;
  final TimeOfDay? preferredGenerationTime;
  final Map<String, String?> generationParams;
  final ThaiFont fontFamily;

  /// UI文言と訳文の言語。初回起動時にストア地域から決まる。
  final AppLanguage appLanguage;

  /// 毎日例文のプッシュ通知を受け取るか
  final bool dailyReminderEnabled;

  /// 通知コーチングダイアログを表示済みか（設定画面の初回表示で一度だけ出す）
  final bool notificationCoachShown;

  const SettingsState({
    required this.isFirstLaunch,
    required this.themeMode,
    this.preferredGenerationTime,
    this.generationParams = const {},
    this.fontFamily = ThaiFont.sarabun,
    this.appLanguage = AppLanguage.ja,
    this.dailyReminderEnabled = true,
    this.notificationCoachShown = true,
  });

  /// 配信希望時刻の「時」。サーバー側は時単位でしか配信しない。
  int get preferredGenerationHour =>
      preferredGenerationTime?.hour ?? kDefaultGenerationHour;

  factory SettingsState.initial() {
    return const SettingsState(
      isFirstLaunch: true,
      themeMode: ThemeMode.light,
      preferredGenerationTime: null,
      generationParams: {},
      fontFamily: ThaiFont.sarabun,
    );
  }

  SettingsState copyWith({
    bool? isFirstLaunch,
    ThemeMode? themeMode,
    TimeOfDay? preferredGenerationTime,
    Map<String, String?>? generationParams,
    ThaiFont? fontFamily,
    AppLanguage? appLanguage,
    bool? dailyReminderEnabled,
    bool? notificationCoachShown,
  }) {
    return SettingsState(
      isFirstLaunch: isFirstLaunch ?? this.isFirstLaunch,
      themeMode: themeMode ?? this.themeMode,
      preferredGenerationTime:
          preferredGenerationTime ?? this.preferredGenerationTime,
      generationParams: generationParams ?? this.generationParams,
      fontFamily: fontFamily ?? this.fontFamily,
      appLanguage: appLanguage ?? this.appLanguage,
      dailyReminderEnabled: dailyReminderEnabled ?? this.dailyReminderEnabled,
      notificationCoachShown:
          notificationCoachShown ?? this.notificationCoachShown,
    );
  }
}

// ==================== Settings Controller ====================

/// Controller for managing app settings
class SettingsController extends StateNotifier<SettingsState> {
  SettingsController(
    this._analytics, {
    PushNotificationService? push,
    StorefrontService? storefront,
  })  : _push = push ?? PushNotificationService(),
        _storefront = storefront ?? StorefrontService(),
        super(SettingsState.initial()) {
    _initialize();
  }

  final AnalyticsService _analytics;
  final PushNotificationService _push;
  final StorefrontService _storefront;
  SharedPreferences? _prefs;

  /// 初期化完了を待つための Completer
  final Completer<void> _initialized = Completer<void>();

  /// 初期化完了を待つ Future
  Future<void> get initialized => _initialized.future;

  /// Initialize settings from storage
  Future<void> _initialize() async {
    _prefs = await SharedPreferences.getInstance();
    await _loadSettings();
    _initialized.complete();
  }

  static const _prefKeyFontFamily = 'pref_font_family';

  static const _generationParamKeys = [
    'style',
    'topic',
    'politeness',
    'grammarFocus',
    'emotion',
  ];

  static String _prefKey(String param) => 'pref_$param';

  /// Load settings from storage
  Future<void> _loadSettings() async {
    if (_prefs == null) return;

    await migrateExistingUserFlags(
      _prefs!,
      DatabaseHelper.instance.hasAnySentence,
    );
    // 移行処理で既存ユーザーには is_first_launch=false を書くため読み直す
    final isFirstLaunch = _prefs!.getBool(AppConfig.prefKeyFirstLaunch) ?? true;
    final themeModeString =
        _prefs!.getString(AppConfig.prefKeyThemeMode) ?? 'light';
    final themeMode = _parseThemeMode(themeModeString);

    // Load preferred generation time
    final timeString =
        _prefs!.getString(AppConfig.prefKeyPreferredGenerationTime);
    final preferredTime = timeString != null ? _parseTime(timeString) : null;

    // Load generation params
    final params = <String, String?>{};
    for (final key in _generationParamKeys) {
      params[key] = _prefs!.getString(_prefKey(key));
    }

    // Load font family
    final fontValue = _prefs!.getString(_prefKeyFontFamily);
    final fontFamily = fontValue != null
        ? ThaiFontExtension.fromPrefValue(fontValue)
        : ThaiFont.sarabun;

    // 毎日例文の通知は既定でオン（アプリ内オプトアウト方式）。実際に届くかは
    // OSの通知許可次第で、拒否・未許可の場合は syncPushRegistration が false に戻す。
    final dailyReminderEnabled =
        _prefs!.getBool(AppConfig.prefKeyDailyReminderEnabled) ?? true;

    // 既存ユーザーにも一度は出す（通知導入前のユーザーはトークン未登録のため）。
    // migrateExistingUserFlags では表示済みにしない。
    final notificationCoachShown =
        _prefs!.getBool(AppConfig.prefKeyNotificationCoachShown) ?? false;

    final appLanguage = await _resolveAppLanguage();

    state = SettingsState(
      isFirstLaunch: isFirstLaunch,
      themeMode: themeMode,
      preferredGenerationTime: preferredTime,
      generationParams: params,
      fontFamily: fontFamily,
      appLanguage: appLanguage,
      dailyReminderEnabled: dailyReminderEnabled,
      notificationCoachShown: notificationCoachShown,
    );
    unawaited(_analytics.setUserAppLanguage(appLanguage.code));
  }

  /// アプリ言語を決める。保存済みならそれが真実。未保存（初回起動）のときだけ
  /// ストア地域を1回読み、日本以外だと確認できた場合に en へ倒す。
  ///
  /// ストア接続を伴うので初回起動時のみ最大3秒待つ（splash の初期化待ちに相乗り）。
  /// 取得できなければ ja のまま＝既存ユーザーの挙動は変わらない。
  Future<AppLanguage> _resolveAppLanguage() async {
    final stored = _prefs!.getString(AppConfig.prefKeyAppLanguage);
    if (stored != null) return AppLanguage.fromCode(stored);

    // dev はストア地域を見ずに ja 固定。開発端末のストアアカウントは日本以外の
    // ことが多く、毎回 en で立ち上がると日本語UIの確認ができない。
    // en の確認は設定の言語切替（dev専用）で行う。
    if (AppConfig.isDev) {
      await _prefs!.setString(AppConfig.prefKeyAppLanguage, AppLanguage.ja.code);
      return AppLanguage.ja;
    }

    final country = await _storefront.countryCode();
    final resolved = AppLanguage.fromStorefront(country);
    await _prefs!.setString(AppConfig.prefKeyAppLanguage, resolved.code);
    unawaited(
      _analytics.logAppLanguageResolved(
        storefront: country,
        lang: resolved.code,
      ),
    );
    unawaited(_push.setAppLanguage(resolved.code));
    return resolved;
  }

  /// アプリ言語を切り替える。
  ///
  /// 訳文は生成時の言語で保存され、切り替えても履歴は書き換わらないので、
  /// 1つの履歴に日英が混在しうる。設定ダイアログの注記でその旨を伝えている。
  /// app_language は users/{uid} にもミラーする（毎日配信バッチはローカルの
  /// SharedPreferences を見られないため）。
  Future<void> setAppLanguage(AppLanguage lang) async {
    if (lang == state.appLanguage) return;
    await _prefs?.setString(AppConfig.prefKeyAppLanguage, lang.code);
    state = state.copyWith(appLanguage: lang);
    unawaited(_push.setAppLanguage(lang.code));
    unawaited(_analytics.setUserAppLanguage(lang.code));
    unawaited(
      _analytics.logChangeSetting(key: 'app_language', value: lang.code),
    );
  }

  /// コーチマーク・オンボーディング導入前からの既存ユーザーに、アップデート後
  /// これらが再表示されるのを防ぐ一度きりの移行処理。
  ///
  /// 既存ユーザーの判定は「ローカルDBに例文がある」を主条件とする
  /// （is_first_launch フラグは旧バージョンで保存されていない場合があるため）。
  /// 既存ユーザーには:
  /// - is_first_launch=false を書き、オンボーディング・初回ダイアログ・コーチ
  ///   再トリガー（home_screen の if(isFirstLaunch) ブロック）をスキップさせる
  /// - コーチマーク各フラグを表示済みにし、通常経路でのコーチ表示も抑止する
  @visibleForTesting
  static Future<void> migrateExistingUserFlags(
    SharedPreferences prefs,
    Future<bool> Function() hasAnySentence,
  ) async {
    if (prefs.getBool(AppConfig.prefKeyCoachMarksMigrated) ?? false) return;
    final storedFirstLaunch =
        prefs.getBool(AppConfig.prefKeyFirstLaunch) ?? true;
    final isExistingUser = !storedFirstLaunch || await hasAnySentence();
    if (isExistingUser) {
      await prefs.setBool(AppConfig.prefKeyFirstLaunch, false);
      await prefs.setBool(AppConfig.prefKeySentenceCoachShown, true);
      await prefs.setBool(AppConfig.prefKeyQuizReviewCoachShown, true);
      await prefs.setBool(AppConfig.prefKeyQuizButtonCoachShown, true);
      await prefs.setBool(AppConfig.prefKeyNextTopicCoachShown, true);
    }
    await prefs.setBool(AppConfig.prefKeyCoachMarksMigrated, true);
  }

  /// 初回起動完了を記録
  Future<void> completeFirstLaunch() async {
    await _prefs?.setBool(AppConfig.prefKeyFirstLaunch, false);
    state = state.copyWith(isFirstLaunch: false);
    unawaited(
      _analytics.logChangeSetting(key: 'first_launch_completed', value: 'true'),
    );
  }

  // ==================== Preferences Management ====================

  /// Set theme mode
  Future<void> setThemeMode(ThemeMode mode) async {
    await _prefs?.setString(
      AppConfig.prefKeyThemeMode,
      mode.toString().split('.').last,
    );
    state = state.copyWith(themeMode: mode);
    unawaited(
      _analytics.logChangeSetting(
        key: 'theme_mode',
        value: mode.toString().split('.').last,
      ),
    );
  }

  /// Set font family
  Future<void> setFontFamily(ThaiFont font) async {
    await _prefs?.setString(_prefKeyFontFamily, font.prefValue);
    state = state.copyWith(fontFamily: font);
    unawaited(
      _analytics.logChangeSetting(key: 'font_family', value: font.prefValue),
    );
  }

  // ==================== Daily Sentence Notification ====================

  /// サインイン後に呼ぶ。OSの許可状態とアプリ内設定を突き合わせる。
  ///
  /// 未許可なら許可ダイアログが出る。拒否された場合はアプリ内設定もオフに倒し、
  /// 「オンなのに届かない」状態が残らないようにする。
  Future<void> syncPushRegistration() async {
    await initialized;
    // 既存ユーザーはテーマを変更するまでサーバー側に設定が無いので、起動時に揃える
    unawaited(_push.setPreferredTopic(state.generationParams['topic']));
    // 初回起動時の言語決定はサインイン前に走り users doc に書けないため、ここで揃える
    unawaited(_push.setAppLanguage(state.appLanguage.code));

    final enabled = await _push.sync(
      desiredEnabled: state.dailyReminderEnabled,
    );
    if (enabled == state.dailyReminderEnabled) return;
    await _prefs?.setBool(AppConfig.prefKeyDailyReminderEnabled, enabled);
    state = state.copyWith(dailyReminderEnabled: enabled);
  }

  /// 毎日例文の通知を切り替える。
  ///
  /// オフにしたときは null を返す。オンにしたときは結果をそのまま返すので、
  /// [PushEnableResult.denied] のときだけ呼び出し側は OS設定へ誘導する案内を
  /// 出すこと（状態はオフに戻る）。[PushEnableResult.pending] は許可済みで
  /// 登録待ちなので、オンのまま何も出さない。
  Future<PushEnableResult?> setDailyReminderEnabled(bool enabled) async {
    // トークン登録・削除はAPNs往復で数秒かかることがある。スイッチが固まって
    // 見えないよう先に表示を切り替え、結果が違ったら戻す。
    state = state.copyWith(dailyReminderEnabled: enabled);

    if (!enabled) {
      await _push.disable();
      await _prefs?.setBool(AppConfig.prefKeyDailyReminderEnabled, false);
      unawaited(
        _analytics.logChangeSetting(
          key: 'daily_reminder_enabled',
          value: 'off',
        ),
      );
      return null;
    }

    final result = await _push.enable();
    // 拒否されたときだけオフに戻す。pending は許可が取れているので維持し、
    // 登録は onTokenRefresh か次回起動の同期に任せる。
    final keepOn = result != PushEnableResult.denied;
    await _prefs?.setBool(AppConfig.prefKeyDailyReminderEnabled, keepOn);
    if (!keepOn) {
      state = state.copyWith(dailyReminderEnabled: false);
    }
    unawaited(
      _analytics.logChangeSetting(
        key: 'daily_reminder_enabled',
        value: result.name,
      ),
    );
    return result;
  }

  /// サインアウト直前に呼ぶ。いま署名中の uid の通知登録だけを解除する。
  ///
  /// fcm_token は端末単位の値なのに users/{uid} に持たせているため、解除せずに
  /// アカウントを切り替えると旧 doc に生きたトークンが残り、同じ端末に
  /// 使ったアカウントの数だけ毎日例文が届く。
  ///
  /// アプリ内設定（dailyReminderEnabled）は端末の意思なので書き換えない。
  /// 次のサインインで syncPushRegistration が新しいトークンを登録し直す。
  Future<void> unregisterPushForSignOut() async {
    await _push.disable();
  }

  /// OSの通知許可が既に得られているか。コーチングダイアログの出し分けに使う。
  /// 取得できなかった場合は null（判定不能）。
  Future<bool?> hasNotificationPermission() => _push.hasPermission();

  /// バナー・音つきの配信まで許可されているか。暫定許可のままなら false。
  Future<bool?> hasProminentNotificationPermission() =>
      _push.hasProminentPermission();

  /// 通知コーチングダイアログを表示済みにする。
  ///
  /// 出したら結果（オンにした／後回し）に関わらず記録する。断られた直後に
  /// 出し直すと通知そのものへの印象が悪くなるため、再表示はしない。
  Future<void> markNotificationCoachShown() async {
    if (state.notificationCoachShown) return;
    await _prefs?.setBool(AppConfig.prefKeyNotificationCoachShown, true);
    state = state.copyWith(notificationCoachShown: true);
  }

  /// 配信希望時刻を設定する。サーバーは時単位でしか配信しないため分は捨てる。
  Future<void> setPreferredGenerationTime(TimeOfDay time) async {
    final hour = time.hour;
    final normalized = TimeOfDay(hour: hour, minute: 0);
    await _prefs?.setString(
      AppConfig.prefKeyPreferredGenerationTime,
      '$hour:00',
    );
    state = state.copyWith(preferredGenerationTime: normalized);
    await _push.setPreferredHour(hour);
    unawaited(
      _analytics.logChangeSetting(
        key: 'preferred_generation_hour',
        value: hour.toString(),
      ),
    );
  }

  /// Set a generation parameter (null = random)
  ///
  /// [logChange] を false にすると設定変更イベントを送らない。ヒアリングの
  /// 回答から初期テーマを入れる場合など、本人がテーマ選択UIを触っていない
  /// ときに使う（テーマ選択の利用率を水増ししない）。
  Future<void> setGenerationParam(
    String key,
    String? value, {
    bool logChange = true,
  }) async {
    if (value == null) {
      await _prefs?.remove(_prefKey(key));
    } else {
      await _prefs?.setString(_prefKey(key), value);
    }
    final updatedParams = Map<String, String?>.from(state.generationParams);
    updatedParams[key] = value;
    state = state.copyWith(generationParams: updatedParams);
    // テーマだけは配信バッチが参照するのでサーバーへミラーする
    if (key == 'topic') unawaited(_push.setPreferredTopic(value));
    if (!logChange) return;
    unawaited(_analytics.logChangeSetting(key: key, value: value ?? 'random'));
  }

  // ==================== Helper Methods ====================

  /// Parse theme mode from string
  ThemeMode _parseThemeMode(String mode) {
    switch (mode.toLowerCase()) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  /// Parse time from string
  TimeOfDay? _parseTime(String timeString) {
    try {
      final parts = timeString.split(':');
      if (parts.length == 2) {
        final hour = int.parse(parts[0]);
        final minute = int.parse(parts[1]);
        return TimeOfDay(hour: hour, minute: minute);
      }
    } catch (e) {
      // Ignore parsing errors
    }
    return null;
  }
}

/// Provider for settings controller
final settingsControllerProvider =
    StateNotifierProvider<SettingsController, SettingsState>((ref) {
  return SettingsController(ref.watch(analyticsServiceProvider));
});

// ==================== Individual Setting Providers ====================

/// Provider for checking if it's first launch
final isFirstLaunchProvider = Provider<bool>((ref) {
  return ref.watch(settingsControllerProvider).isFirstLaunch;
});

/// Provider for theme mode
final themeModeProvider = Provider<ThemeMode>((ref) {
  return ref.watch(settingsControllerProvider).themeMode;
});

/// Provider for generation params
final generationParamsProvider = Provider<Map<String, String?>>((ref) {
  return ref.watch(settingsControllerProvider).generationParams;
});

/// Provider for font family
final fontFamilyProvider = Provider<ThaiFont>((ref) {
  return ref.watch(settingsControllerProvider).fontFamily;
});

/// Provider for app language (UI文言・訳文の言語)
final appLanguageProvider = Provider<AppLanguage>((ref) {
  return ref.watch(settingsControllerProvider).appLanguage;
});

/// Provider for daily sentence notification toggle
final dailyReminderEnabledProvider = Provider<bool>((ref) {
  return ref.watch(settingsControllerProvider).dailyReminderEnabled;
});

/// Provider for notification coaching dialog shown flag
final notificationCoachShownProvider = Provider<bool>((ref) {
  return ref.watch(settingsControllerProvider).notificationCoachShown;
});
