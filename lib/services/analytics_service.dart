import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AnalyticsService {
  AnalyticsService._internal()
      : _analytics = FirebaseAnalytics.instance,
        observer = FirebaseAnalyticsObserver(
          analytics: FirebaseAnalytics.instance,
          // Dialog や BottomSheet の内部 route は除外し、PageRoute のみ自動計測する。
          routeFilter: (route) => route is PageRoute<dynamic>,
        );

  static final AnalyticsService instance = AnalyticsService._internal();

  final FirebaseAnalytics _analytics;
  final FirebaseAnalyticsObserver observer;

  String? _lastUserId;
  String? _lastTier;

  Future<void> setUserId(String? userId) async {
    if (_lastUserId == userId) return;
    _lastUserId = userId;
    try {
      await _analytics.setUserId(id: userId);
    } on PlatformException catch (error, stackTrace) {
      _logPlatformFailure('setUserId', error, stackTrace);
    } catch (error, stackTrace) {
      _logPlatformFailure('setUserId', error, stackTrace);
    }
  }

  Future<void> setUserTier(String tier) async {
    if (_lastTier == tier) return;
    _lastTier = tier;
    try {
      await _analytics.setUserProperty(name: 'tier', value: tier);
    } on PlatformException catch (error, stackTrace) {
      _logPlatformFailure('setUserProperty', error, stackTrace);
    } catch (error, stackTrace) {
      _logPlatformFailure('setUserProperty', error, stackTrace);
    }
  }

  Future<void> logScreenView({
    required String screenName,
    String? screenClass,
  }) async {
    try {
      await _analytics.logScreenView(
        screenName: screenName,
        screenClass: screenClass ?? screenName,
      );
    } on PlatformException catch (error, stackTrace) {
      _logPlatformFailure('logScreenView', error, stackTrace);
    } catch (error, stackTrace) {
      _logPlatformFailure('logScreenView', error, stackTrace);
    }
  }

  Future<void> logGenerateSentence({
    required String tier,
    String? topic,
    required String source,
    int? count,
  }) async {
    await _logEvent('generate_sentence', {
      'tier': tier,
      'topic': topic,
      'source': source,
      'count': count,
    });
  }

  Future<void> logViewDetail({
    String? sentenceId,
    required String source,
  }) async {
    await _logEvent('view_detail', {
      'sentence_id': sentenceId,
      'source': source,
    });
  }

  Future<void> logPlayTts({
    required String contentType,
    required String text,
    String? sentenceId,
    required String source,
  }) async {
    await _logEvent('play_tts', {
      'content_type': contentType,
      'text': _truncate(text),
      'sentence_id': sentenceId,
      'source': source,
    });
  }

  Future<void> logQuizStart({
    required String category,
    int? questionCount,
  }) async {
    await _logEvent('quiz_start', {
      'category': category,
      'question_count': questionCount,
    });
  }

  Future<void> logQuizAnswer({
    required bool correct,
    required String category,
    int? questionIndex,
  }) async {
    await _logEvent('quiz_answer', {
      'correct': correct ? 1 : 0,
      'category': category,
      'question_index': questionIndex,
    });
  }

  Future<void> logTapPaywall({required String source}) async {
    await _logEvent('tap_paywall', {'source': source});
  }

  Future<void> logTapVocabScore({
    required String source,
    required int vocab,
    required bool isPremium,
  }) async {
    await _logEvent('tap_vocab_score', {
      'source': source,
      'vocab': vocab,
      'is_premium': isPremium ? 1 : 0,
    });
  }

  Future<void> logSubscribe({required String source}) async {
    await _logEvent('subscribe', {'source': source});
  }

  Future<void> logOnboardingStart() async {
    await _logEvent('onboarding_start', {});
  }

  Future<void> logOnboardingComplete({required bool skipped}) async {
    await _logEvent('onboarding_complete', {'skipped': skipped ? 1 : 0});
  }

  Future<void> logSummaryQuizComplete({
    required int score,
    required int questionCount,
    int? vocabBefore,
    int? vocabAfter,
  }) async {
    await _logEvent('summary_quiz_complete', {
      'score': score,
      'question_count': questionCount,
      'vocab_before': vocabBefore,
      'vocab_after': vocabAfter,
    });
  }

  /// 通知コーチングの表示と結果。
  ///
  /// [action] は shown（表示）/ accepted（わかった）/ dismissed（明示的な選択なし）。
  /// 実際に通知がオンになったかは change_setting(daily_reminder_enabled) で見る。
  /// shown を分母に、そこまでの離脱段階を切り分けるために出している。
  Future<void> logNotificationCoach({required String action}) async {
    await _logEvent('notification_coach', {'action': action});
  }

  Future<void> logChangeSetting({
    required String key,
    String? value,
  }) async {
    await _logEvent('change_setting', {
      'key': key,
      'value': value,
    });
  }

  Future<void> _logEvent(
    String name,
    Map<String, Object?> parameters,
  ) async {
    try {
      final normalized = <String, Object>{};
      for (final entry in parameters.entries) {
        final value = entry.value;
        if (value == null) continue;
        if (value is String) {
          // GA4 のパラメータ長超過を避けるため、文字列はここで丸める。
          normalized[entry.key] = _truncate(value);
        } else if (value is num) {
          normalized[entry.key] = value;
        }
      }

      await _analytics.logEvent(
        name: name,
        parameters: normalized.isEmpty ? null : normalized,
      );
    } catch (error, stackTrace) {
      debugPrint('Analytics event failed: $name $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  String _truncate(String value, {int maxLength = 100}) {
    if (value.length <= maxLength) return value;
    return value.substring(0, maxLength);
  }

  void _logPlatformFailure(
    String operation,
    Object error,
    StackTrace stackTrace,
  ) {
    debugPrint('Analytics $operation failed: $error');
    debugPrintStack(stackTrace: stackTrace);
  }
}
