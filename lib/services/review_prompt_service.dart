import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/config/app_config.dart';

enum ReviewPromptOutcome {
  requested,
  skippedUnsupportedPlatform,
  skippedNotEnoughExperience,
  skippedLowSessionScore,
  skippedAlreadyRequestedThisVersion,
  skippedCooldown,
  skippedUnavailable,
  failed,
}

class ReviewPromptService {
  ReviewPromptService({
    MethodChannel? channel,
    SharedPreferences? preferences,
    TargetPlatform? platform,
    DateTime Function()? now,
  })  : _channel = channel ?? const MethodChannel(_channelName),
        _preferences = preferences,
        _platform = platform ?? defaultTargetPlatform,
        _now = now ?? DateTime.now;

  static const _channelName = 'thai_memo/review_prompt';
  static const _completedQuizSessionsKey =
      'review_prompt_completed_quiz_sessions';
  static const _lastRequestedAtKey = 'review_prompt_last_requested_at';
  static const _lastRequestedVersionKey =
      'review_prompt_last_requested_version';

  @visibleForTesting
  static const minCompletedQuizSessions = 4;

  @visibleForTesting
  static const minTotalAnswered = 20;

  @visibleForTesting
  static const minSessionAccuracy = 0.8;

  @visibleForTesting
  static const cooldown = Duration(days: 60);

  final MethodChannel _channel;
  SharedPreferences? _preferences;
  final TargetPlatform _platform;
  final DateTime Function() _now;

  Future<ReviewPromptOutcome> maybeRequestAfterQuizCompleted({
    required int sessionCorrect,
    required int sessionTotal,
    required int totalAnswered,
  }) async {
    if (sessionTotal <= 0) {
      return ReviewPromptOutcome.skippedNotEnoughExperience;
    }

    final preferences = await _prefs;
    final completedQuizSessions =
        (preferences.getInt(_completedQuizSessionsKey) ?? 0) + 1;
    await preferences.setInt(
      _completedQuizSessionsKey,
      completedQuizSessions,
    );

    if (_platform != TargetPlatform.iOS) {
      // Android support can be added behind this same service later.
      return ReviewPromptOutcome.skippedUnsupportedPlatform;
    }

    if (completedQuizSessions < minCompletedQuizSessions ||
        totalAnswered < minTotalAnswered) {
      return ReviewPromptOutcome.skippedNotEnoughExperience;
    }

    final sessionAccuracy = sessionCorrect / sessionTotal;
    if (sessionAccuracy < minSessionAccuracy) {
      return ReviewPromptOutcome.skippedLowSessionScore;
    }

    final appVersion = await _currentAppVersion();
    final lastRequestedVersion =
        preferences.getString(_lastRequestedVersionKey);
    if (lastRequestedVersion == appVersion) {
      return ReviewPromptOutcome.skippedAlreadyRequestedThisVersion;
    }

    final lastRequestedAtMs = preferences.getInt(_lastRequestedAtKey);
    if (lastRequestedAtMs != null) {
      final lastRequestedAt =
          DateTime.fromMillisecondsSinceEpoch(lastRequestedAtMs);
      if (_now().difference(lastRequestedAt) < cooldown) {
        return ReviewPromptOutcome.skippedCooldown;
      }
    }

    try {
      final requested =
          await _channel.invokeMethod<bool>('requestReview') ?? false;
      if (!requested) {
        return ReviewPromptOutcome.skippedUnavailable;
      }

      await preferences.setInt(
        _lastRequestedAtKey,
        _now().millisecondsSinceEpoch,
      );
      await preferences.setString(_lastRequestedVersionKey, appVersion);
      return ReviewPromptOutcome.requested;
    } on PlatformException {
      return ReviewPromptOutcome.failed;
    } on MissingPluginException {
      return ReviewPromptOutcome.failed;
    }
  }

  Future<String> _currentAppVersion() async {
    try {
      final version = await _channel.invokeMethod<String>('getAppVersion');
      if (version != null && version.isNotEmpty) {
        return version;
      }
    } on PlatformException {
      // Fall through to the Dart-side constant so review prompting still works.
    } on MissingPluginException {
      // Fall through to the Dart-side constant so review prompting still works.
    }
    return AppConfig.appVersion;
  }

  Future<SharedPreferences> get _prefs async {
    return _preferences ??= await SharedPreferences.getInstance();
  }
}
