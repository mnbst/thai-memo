import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/config/app_config.dart';

// ==================== Settings State ====================

/// Settings state class
class SettingsState {
  final bool isFirstLaunch;
  final bool notificationsEnabled;
  final ThemeMode themeMode;
  final TimeOfDay? preferredGenerationTime;

  const SettingsState({
    required this.isFirstLaunch,
    required this.notificationsEnabled,
    required this.themeMode,
    this.preferredGenerationTime,
  });

  factory SettingsState.initial() {
    return const SettingsState(
      isFirstLaunch: true,
      notificationsEnabled: true,
      themeMode: ThemeMode.system,
      preferredGenerationTime: null,
    );
  }

  SettingsState copyWith({
    bool? isFirstLaunch,
    bool? notificationsEnabled,
    ThemeMode? themeMode,
    TimeOfDay? preferredGenerationTime,
  }) {
    return SettingsState(
      isFirstLaunch: isFirstLaunch ?? this.isFirstLaunch,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      themeMode: themeMode ?? this.themeMode,
      preferredGenerationTime:
          preferredGenerationTime ?? this.preferredGenerationTime,
    );
  }
}

// ==================== Settings Controller ====================

/// Controller for managing app settings
class SettingsController extends StateNotifier<SettingsState> {
  SharedPreferences? _prefs;

  SettingsController() : super(SettingsState.initial()) {
    _initialize();
  }

  /// Initialize settings from storage
  Future<void> _initialize() async {
    _prefs = await SharedPreferences.getInstance();
    await _loadSettings();
  }

  /// Load settings from storage
  Future<void> _loadSettings() async {
    if (_prefs == null) return;

    final isFirstLaunch =
        _prefs!.getBool(AppConfig.prefKeyFirstLaunch) ?? true;
    final notificationsEnabled =
        _prefs!.getBool(AppConfig.prefKeyNotificationsEnabled) ?? true;
    final themeModeString =
        _prefs!.getString(AppConfig.prefKeyThemeMode) ?? 'system';
    final themeMode = _parseThemeMode(themeModeString);

    // Load preferred generation time
    final timeString =
        _prefs!.getString(AppConfig.prefKeyPreferredGenerationTime);
    final preferredTime = timeString != null ? _parseTime(timeString) : null;

    state = SettingsState(
      isFirstLaunch: isFirstLaunch,
      notificationsEnabled: notificationsEnabled,
      themeMode: themeMode,
      preferredGenerationTime: preferredTime,
    );
  }

  // ==================== Preferences Management ====================

  /// Set first launch flag
  Future<void> setFirstLaunchCompleted() async {
    await _prefs?.setBool(AppConfig.prefKeyFirstLaunch, false);
    state = state.copyWith(isFirstLaunch: false);
  }

  /// Toggle notifications
  Future<void> toggleNotifications(bool enabled) async {
    await _prefs?.setBool(AppConfig.prefKeyNotificationsEnabled, enabled);
    state = state.copyWith(notificationsEnabled: enabled);
  }

  /// Set theme mode
  Future<void> setThemeMode(ThemeMode mode) async {
    await _prefs?.setString(
      AppConfig.prefKeyThemeMode,
      mode.toString().split('.').last,
    );
    state = state.copyWith(themeMode: mode);
  }

  /// Set preferred generation time
  Future<void> setPreferredGenerationTime(TimeOfDay time) async {
    final timeString = '${time.hour}:${time.minute}';
    await _prefs?.setString(
      AppConfig.prefKeyPreferredGenerationTime,
      timeString,
    );
    state = state.copyWith(preferredGenerationTime: time);
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
  return SettingsController();
});

// ==================== Individual Setting Providers ====================

/// Provider for checking if it's first launch
final isFirstLaunchProvider = Provider<bool>((ref) {
  return ref.watch(settingsControllerProvider).isFirstLaunch;
});

/// Provider for notifications enabled status
final notificationsEnabledProvider = Provider<bool>((ref) {
  return ref.watch(settingsControllerProvider).notificationsEnabled;
});

/// Provider for theme mode
final themeModeProvider = Provider<ThemeMode>((ref) {
  return ref.watch(settingsControllerProvider).themeMode;
});
