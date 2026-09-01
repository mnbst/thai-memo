import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  static const _generatedSentencesKey = 'review_prompt_generated_sentences';
  static const _activeDaysKey = 'review_prompt_active_days';
  static const _lastRequestedAtKey = 'review_prompt_last_requested_at';
  static const _lastRequestedVersionKey =
      'review_prompt_last_requested_version';

  // クイズ経路のしきい値。実データではクイズ未解答のユーザーが4割強、
  // 解答済みでも平均14問だったため、旧値（4セッション / 20問）ではほぼ誰にも
  // 依頼が出ていなかった。評価母数が増えないと星1件の影響が薄まらない。
  @visibleForTesting
  static const minCompletedQuizSessions = 2;

  @visibleForTesting
  static const minTotalAnswered = 10;

  @visibleForTesting
  static const minSessionAccuracy = 0.8;

  // 例文生成経路のしきい値。クイズに到達しない層を拾うのが目的。
  // 初日に依頼して低評価を招かないよう、日をまたいだ利用を必須にする。
  @visibleForTesting
  static const minGeneratedSentences = 8;

  @visibleForTesting
  static const minActiveDays = 3;

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

    return _request(preferences);
  }

  /// 例文生成のたびに呼ぶ。クイズに来ない層にも依頼を届けるための経路。
  ///
  /// 生成回数と「利用した日数」はこのサービス内で数える。呼び出し側に集計を
  /// 持たせると、経路が増えるたびに数え漏れが起きるため。
  Future<ReviewPromptOutcome> maybeRequestAfterSentenceGenerated() async {
    final preferences = await _prefs;

    final generated = (preferences.getInt(_generatedSentencesKey) ?? 0) + 1;
    await preferences.setInt(_generatedSentencesKey, generated);

    final today = _todayKey();
    final activeDays = preferences.getStringList(_activeDaysKey) ?? const [];
    if (!activeDays.contains(today)) {
      // しきい値の判定に必要なのは日数だけなので、上限を超えたら捨てて良い。
      final updated = [...activeDays, today];
      await preferences.setStringList(
        _activeDaysKey,
        updated.length > minActiveDays
            ? updated.sublist(updated.length - minActiveDays)
            : updated,
      );
    }

    if (_platform != TargetPlatform.iOS) {
      return ReviewPromptOutcome.skippedUnsupportedPlatform;
    }

    final dayCount =
        (preferences.getStringList(_activeDaysKey) ?? const []).length;
    if (generated < minGeneratedSentences || dayCount < minActiveDays) {
      return ReviewPromptOutcome.skippedNotEnoughExperience;
    }

    return _request(preferences);
  }

  /// バージョン・クールダウンの共通ガードを通してから OS の依頼ダイアログを出す。
  /// 経路が増えても二重に依頼しないよう、記録はここに集約する。
  Future<ReviewPromptOutcome> _request(SharedPreferences preferences) async {
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

  String _todayKey() {
    final now = _now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}'
        '-${now.day.toString().padLeft(2, '0')}';
  }

  Future<String> _currentAppVersion() async {
    try {
      final version = await _channel.invokeMethod<String>('getAppVersion');
      if (version != null && version.isNotEmpty) {
        return version;
      }
    } on PlatformException {
      // Fall through to PackageInfo so review prompting still works.
    } on MissingPluginException {
      // Fall through to PackageInfo so review prompting still works.
    }
    try {
      final info = await PackageInfo.fromPlatform();
      if (info.version.isNotEmpty) {
        return info.version;
      }
    } catch (_) {
      // 版が分からないときは空で扱う。定数に焼くと更新漏れで版が固定され、
      // 「このバージョンでは依頼済み」の判定が永久に効かなくなる。
    }
    return '';
  }

  Future<SharedPreferences> get _prefs async {
    return _preferences ??= await SharedPreferences.getInstance();
  }
}
