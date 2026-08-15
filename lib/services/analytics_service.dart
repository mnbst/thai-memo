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
  String? _lastAppLanguage;

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
      // 'sentence_id': sentenceId,
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
      // 'text': _truncate(text),
      // 'sentence_id': sentenceId,
      'source': source,
    });
  }

  Future<void> logQuizStart({
    required String category,
    int? questionCount,
    String? source,
  }) async {
    await _logEvent('quiz_start', {
      'category': category,
      'question_count': questionCount,
      'source': source,
    });
  }

  Future<void> logQuizAnswer({
    required bool correct,
    required String category,
    int? questionIndex,
    String? source,
  }) async {
    await _logEvent('quiz_answer', {
      'correct': correct ? 1 : 0,
      'category': category,
      // 'question_index': questionIndex,
      'source': source,
    });
  }

  /// 例文から1問確認クイズへ進む導線A/Bテストのファネル。
  ///
  /// [action] は assigned / shown / tapped / started / answered / error。
  /// [source] は端末に固定した実験群を表す。既存のGA4カスタム
  /// ディメンションだけで集計できるよう、パラメータはaction/sourceに限定する。
  Future<void> logQuizOffer({
    required String action,
    required String source,
  }) async {
    await _logEvent('quiz_offer', {'action': action, 'source': source});
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

  /// 発音練習の1回ぶん。
  ///
  /// パラメータは GA4 側で登録しないと (not set) になり、しかも遡及しない。
  /// 登録先は型で決まる。文字列は customDimension、数値は customMetric。
  /// 数値をディメンションで登録しても値は読めず (not set) のままになる。
  /// 登録済み: source(dim) / worst_tone(dim) / score(metric) /
  /// recognized_pct(metric)。source は他イベントと共有のディメンションなので、
  /// 画面別に見るときは eventName でも絞ること。
  /// monotone は 0|1 の数値なので dim 登録は無効。metric に直すこと。
  Future<void> logPronunciationAttempt({
    required String sentenceId,
    required String source,
    required double score,
    required int syllableCount,
    required bool monotone,
    required String worstTone,
    double? recognizedRatio,
  }) async {
    await _logEvent('pronunciation_attempt', {
      // 'sentence_id': sentenceId,
      // どの画面から練習したか（home_card / detail / sheet）。
      // 文字列なので customDimension 側の source を再利用する。
      'source': source,
      'score': score.round(),
      'syllable_count': syllableCount,
      'monotone': monotone ? 1 : 0,
      'worst_tone': worstTone,
      // 音声認識に非対応の端末では送らない。判定できないことと
      // 判定して駄目だったことを分析上も混同させない。
      if (recognizedRatio != null)
        'recognized_pct': (recognizedRatio * 100).round(),
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

  /// アプリ言語をユーザープロパティにする。全指標を言語で割るために使う。
  Future<void> setUserAppLanguage(String lang) async {
    if (_lastAppLanguage == lang) return;
    _lastAppLanguage = lang;
    try {
      await _analytics.setUserProperty(name: 'app_language', value: lang);
    } on PlatformException catch (error, stackTrace) {
      _logPlatformFailure('setUserProperty', error, stackTrace);
    } catch (error, stackTrace) {
      _logPlatformFailure('setUserProperty', error, stackTrace);
    }
  }

  /// 初回起動時の言語決定の結果。1ユーザーにつき1回だけ出る。
  ///
  /// [storefront] が unknown の割合＝ストア地域の取得失敗率。失敗すると日本の
  /// ユーザーでも英語で起動してしまうため、無視できない水準なら初期値の
  /// フォールバック規則を見直す。
  Future<void> logAppLanguageResolved({
    required String? storefront,
    required String lang,
  }) async {
    await _logEvent('app_language_resolved', {
      'storefront': storefront ?? 'unknown',
      'lang': lang,
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

  /// プレミアム体験トライアル終了案内の表示と結果。
  ///
  /// [action] は shown（表示）/ accepted（プレミアムを見る）/ dismissed（あとで）。
  /// shown が「体験を使い切った人数」の分母になる。開いた先の行動は
  /// tap_paywall(source: trial_ended) と subscribe(source: trial_ended) で追う。
  Future<void> logPremiumTrialEnded({required String action}) async {
    await _logEvent('premium_trial_ended', {'action': action});
  }

  /// 既存ユーザーへ後から配ったプレミアム体験の、開放案内の表示。
  ///
  /// [action] は shown（表示）のみ。ここでは課金を勧めないので選択肢がない。
  /// この shown が「体験を実際に認識した人数」の分母になり、
  /// premium_trial_ended(shown) → subscribe への転換率をここから測る。
  Future<void> logPremiumTrialStarted({required String action}) async {
    await _logEvent('premium_trial_started', {'action': action});
  }

  /// 例文タブの常設プレミアムバナーの表示と結果。
  ///
  /// [action] は shown（表示）/ dismissed（×で閉じた）。タップして開いた場合は
  /// tap_paywall(source: learning_banner_*) 側で拾えるのでここでは出さない。
  /// shown を分母にして、訴求軸（[source]）ごとの反応率を比較するために出している。
  Future<void> logPaywallBanner({
    required String action,
    required String source,
  }) async {
    await _logEvent('paywall_banner', {'action': action, 'source': source});
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
