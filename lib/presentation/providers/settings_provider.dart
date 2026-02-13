import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/config/app_config.dart';
import '../../domain/usecases/save_sentence_usecase.dart';
import 'sentence_provider.dart';

// ==================== Settings State ====================

/// Settings state class
class SettingsState {
  final bool isFirstLaunch;
  final bool notificationsEnabled;
  final ThemeMode themeMode;
  final TimeOfDay? preferredGenerationTime;
  final bool hasApiKey;
  final String? maskedApiKey;

  const SettingsState({
    required this.isFirstLaunch,
    required this.notificationsEnabled,
    required this.themeMode,
    this.preferredGenerationTime,
    required this.hasApiKey,
    this.maskedApiKey,
  });

  factory SettingsState.initial() {
    return const SettingsState(
      isFirstLaunch: true,
      notificationsEnabled: true,
      themeMode: ThemeMode.system,
      preferredGenerationTime: null,
      hasApiKey: false,
      maskedApiKey: null,
    );
  }

  SettingsState copyWith({
    bool? isFirstLaunch,
    bool? notificationsEnabled,
    ThemeMode? themeMode,
    TimeOfDay? preferredGenerationTime,
    bool? hasApiKey,
    String? maskedApiKey,
  }) {
    return SettingsState(
      isFirstLaunch: isFirstLaunch ?? this.isFirstLaunch,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      themeMode: themeMode ?? this.themeMode,
      preferredGenerationTime:
          preferredGenerationTime ?? this.preferredGenerationTime,
      hasApiKey: hasApiKey ?? this.hasApiKey,
      maskedApiKey: maskedApiKey ?? this.maskedApiKey,
    );
  }
}

// ==================== Settings Controller ====================

/// Controller for managing app settings
class SettingsController extends StateNotifier<SettingsState> {
  final SaveSentenceUseCase _saveUseCase;
  SharedPreferences? _prefs;

  SettingsController(this._saveUseCase) : super(SettingsState.initial()) {
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

    // Check API key
    final hasApiKey = await _saveUseCase.hasApiKey();
    final maskedApiKey = await _saveUseCase.getMaskedApiKey();

    state = SettingsState(
      isFirstLaunch: isFirstLaunch,
      notificationsEnabled: notificationsEnabled,
      themeMode: themeMode,
      preferredGenerationTime: preferredTime,
      hasApiKey: hasApiKey,
      maskedApiKey: maskedApiKey,
    );
  }

  // ==================== API Key Management ====================

  /// Save API key
  Future<bool> saveApiKey(String apiKey) async {
    try {
      await _saveUseCase.saveApiKey(apiKey);
      final maskedApiKey = await _saveUseCase.getMaskedApiKey();
      state = state.copyWith(
        hasApiKey: true,
        maskedApiKey: maskedApiKey,
      );
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Get API key (for display/validation)
  Future<String?> getApiKey() async {
    try {
      return await _saveUseCase.getApiKey();
    } catch (e) {
      return null;
    }
  }

  /// Delete API key
  Future<void> deleteApiKey() async {
    try {
      await _saveUseCase.deleteApiKey();
      state = state.copyWith(
        hasApiKey: false,
        maskedApiKey: null,
      );
    } catch (e) {
      // Handle error
    }
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

  /// Refresh API key status
  Future<void> refreshApiKeyStatus() async {
    final hasApiKey = await _saveUseCase.hasApiKey();
    final maskedApiKey = await _saveUseCase.getMaskedApiKey();
    state = state.copyWith(
      hasApiKey: hasApiKey,
      maskedApiKey: maskedApiKey,
    );
  }
}

/// Provider for settings controller
final settingsControllerProvider =
    StateNotifierProvider<SettingsController, SettingsState>((ref) {
  final saveUseCase = ref.watch(saveSentenceUseCaseProvider);
  return SettingsController(saveUseCase);
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

/// Provider for API key status
final hasApiKeyProvider = Provider<bool>((ref) {
  return ref.watch(settingsControllerProvider).hasApiKey;
});

/// Provider for masked API key
final maskedApiKeyProvider = Provider<String?>((ref) {
  return ref.watch(settingsControllerProvider).maskedApiKey;
});
