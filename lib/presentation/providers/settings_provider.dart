import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/config/app_config.dart';
import '../../data/datasources/local/database_helper.dart';
import '../../services/analytics_service.dart';
import '../../services/push_notification_service.dart';
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

  /// 毎日例文のプッシュ通知を受け取るか
  final bool dailyReminderEnabled;

  const SettingsState({
    required this.isFirstLaunch,
    required this.themeMode,
    this.preferredGenerationTime,
    this.generationParams = const {},
    this.fontFamily = ThaiFont.sarabun,
    this.dailyReminderEnabled = true,
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
    bool? dailyReminderEnabled,
  }) {
    return SettingsState(
      isFirstLaunch: isFirstLaunch ?? this.isFirstLaunch,
      themeMode: themeMode ?? this.themeMode,
      preferredGenerationTime:
          preferredGenerationTime ?? this.preferredGenerationTime,
      generationParams: generationParams ?? this.generationParams,
      fontFamily: fontFamily ?? this.fontFamily,
      dailyReminderEnabled: dailyReminderEnabled ?? this.dailyReminderEnabled,
    );
  }
}

// ==================== Settings Controller ====================

/// Controller for managing app settings
class SettingsController extends StateNotifier<SettingsState> {
  SettingsController(this._analytics, {PushNotificationService? push})
      : _push = push ?? PushNotificationService(),
        super(SettingsState.initial()) {
    _initialize();
  }

  final AnalyticsService _analytics;
  final PushNotificationService _push;
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
    // OSの通知許可次第で、拒否されている場合は syncPushRegistration が false に戻す。
    final dailyReminderEnabled =
        _prefs!.getBool(AppConfig.prefKeyDailyReminderEnabled) ?? true;

    state = SettingsState(
      isFirstLaunch: isFirstLaunch,
      themeMode: themeMode,
      preferredGenerationTime: preferredTime,
      generationParams: params,
      fontFamily: fontFamily,
      dailyReminderEnabled: dailyReminderEnabled,
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

    final enabled = await _push.sync(
      desiredEnabled: state.dailyReminderEnabled,
    );
    if (enabled == state.dailyReminderEnabled) return;
    await _prefs?.setBool(AppConfig.prefKeyDailyReminderEnabled, enabled);
    state = state.copyWith(dailyReminderEnabled: enabled);
  }

  /// 毎日例文の通知を切り替える。
  ///
  /// オンにした際にOSの許可が得られなければ false を返す。呼び出し側は
  /// OS設定へ誘導する案内を出すこと（状態はオフのままになる）。
  Future<bool> setDailyReminderEnabled(bool enabled) async {
    // トークン登録・削除はAPNs往復で数秒かかることがある。スイッチが固まって
    // 見えないよう先に表示を切り替え、結果が違ったら戻す。
    state = state.copyWith(dailyReminderEnabled: enabled);

    final applied = enabled ? await _push.enable() : false;
    if (!enabled) await _push.disable();

    await _prefs?.setBool(AppConfig.prefKeyDailyReminderEnabled, applied);
    if (applied != enabled) {
      state = state.copyWith(dailyReminderEnabled: applied);
    }
    unawaited(
      _analytics.logChangeSetting(
        key: 'daily_reminder_enabled',
        value: applied.toString(),
      ),
    );
    return applied == enabled;
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
  Future<void> setGenerationParam(String key, String? value) async {
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

/// Provider for daily sentence notification toggle
final dailyReminderEnabledProvider = Provider<bool>((ref) {
  return ref.watch(settingsControllerProvider).dailyReminderEnabled;
});
