import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/config/app_config.dart';
import '../../services/analytics_service.dart';
import 'analytics_provider.dart';

// ==================== Font Family ====================

enum ThaiFont { notoSansThai, mitr, sarabun, krub }

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
      orElse: () => ThaiFont.notoSansThai,
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

  const SettingsState({
    required this.isFirstLaunch,
    required this.themeMode,
    this.preferredGenerationTime,
    this.generationParams = const {},
    this.fontFamily = ThaiFont.notoSansThai,
  });

  factory SettingsState.initial() {
    return const SettingsState(
      isFirstLaunch: true,
      themeMode: ThemeMode.light,
      preferredGenerationTime: null,
      generationParams: {},
      fontFamily: ThaiFont.notoSansThai,
    );
  }

  SettingsState copyWith({
    bool? isFirstLaunch,
    ThemeMode? themeMode,
    TimeOfDay? preferredGenerationTime,
    Map<String, String?>? generationParams,
    ThaiFont? fontFamily,
  }) {
    return SettingsState(
      isFirstLaunch: isFirstLaunch ?? this.isFirstLaunch,
      themeMode: themeMode ?? this.themeMode,
      preferredGenerationTime:
          preferredGenerationTime ?? this.preferredGenerationTime,
      generationParams: generationParams ?? this.generationParams,
      fontFamily: fontFamily ?? this.fontFamily,
    );
  }
}

// ==================== Settings Controller ====================

/// Controller for managing app settings
class SettingsController extends StateNotifier<SettingsState> {
  SettingsController(this._analytics) : super(SettingsState.initial()) {
    _initialize();
  }

  final AnalyticsService _analytics;
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
        : ThaiFont.notoSansThai;

    state = SettingsState(
      isFirstLaunch: isFirstLaunch,
      themeMode: themeMode,
      preferredGenerationTime: preferredTime,
      generationParams: params,
      fontFamily: fontFamily,
    );
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
