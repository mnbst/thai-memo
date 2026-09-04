import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/config/app_config.dart';
import '../../core/constants/generation_constants.dart';
import '../../core/quota_error.dart';
import '../../core/theme/app_colors.dart';
import '../../l10n/app_localizations.dart';
import '../../data/models/syllable.dart';
import '../../data/models/thai_sentence.dart';
import '../../data/models/word_breakdown.dart';
import '../../services/app_version_reporter.dart';
import '../../services/daily_sentence_service.dart';
import '../../services/interview_reporter.dart';
import '../../services/push_notification_service.dart';
import '../providers/analytics_provider.dart';
import '../providers/sentence_provider.dart';
import '../providers/quiz_provider.dart';
import '../providers/quiz_offer_experiment_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/tts_provider.dart';
import '../providers/remaining_quota_provider.dart';
import '../providers/review_prompt_provider.dart';
import '../providers/vocab_stats_provider.dart';
import '../widgets/notification_coach_dialog.dart';
import '../widgets/topic_picker.dart';
import '../widgets/premium_trial_ended_dialog.dart';
import '../widgets/premium_trial_started_dialog.dart';
import '../widgets/quiz_offer.dart';
import '../widgets/sentence_audio_section.dart';
import '../widgets/thai_highlight.dart';
import '../widgets/sign_in_reminder_banner.dart';
import '../widgets/loading_tip_carousel.dart';
import '../widgets/vocab_level.dart';
import 'detail_screen.dart';
import 'history_screen.dart';
import 'interview_screen.dart';
import 'onboarding_screen.dart';
import 'vocab_test_screen.dart';
import 'guide_screen.dart';
import 'paywall_screen.dart';
import 'quiz_screen.dart';
import 'settings_screen.dart';

/// 例文の生成上限に当たった画面から開くペイウォールの source。
/// paywall_banner(shown) と tap_paywall で同じ値を使い、CTR を
/// learning_banner_* と同じ形で比べられるようにしている。
const String _quotaPaywallSource = 'sentence_quota_error';

/// Home screen with bottom navigation
class HomeScreen extends ConsumerStatefulWidget {
  static const routeName = 'home';

  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with WidgetsBindingObserver, RouteAware {
  int _currentIndex = 0;

  /// 設定タブの位置。通知の案内はここへ移ってから出す。
  static const int _settingsTabIndex = 2;
  bool _initialLoadCompleted = false;
  Future<void>? _initialLoadFuture;
  final _dailySentenceService = DailySentenceService();
  final _learningKey = GlobalKey<_LearningScreenState>();
  StreamSubscription<RemoteMessage>? _notificationOpenSubscription;
  ModalRoute<dynamic>? _analyticsRoute;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _logCurrentTabScreen();
      // サーバーが「この端末のアプリが何を持っているか」を知るための記録。
      // 学習の導線とは無関係なので待たない。
      unawaited(AppVersionReporter().report());
      // 初回起動で書けなかったヒアリング回答を送り直す（送信済みなら何もしない）。
      unawaited(InterviewReporter().report());
      _notificationOpenSubscription =
          FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationOpen);
      _loadInitialSentenceThenHandleNotification();
      // remaining_sentences監視: 0→正数（dailyBatchリセット）で自動読み込み
      ref.listenManual(remainingSentencesProvider, (prev, next) {
        if (!_initialLoadCompleted) return;
        if (!changedFromNoRemainingToAvailable(prev, next)) return;

        final data = ref.read(userDocProvider).valueOrNull;
        final isGenerated =
            (data?['daily_sentence_generated'] as bool?) ?? false;
        if (shouldAutoLoadAfterSentenceQuotaRefresh(
          previous: prev,
          next: next,
          dailySentenceGenerated: isGenerated,
        )) {
          // dailyBatchリセット時は表示中でも新日の例文を生成。
          // 購入・復元などでquotaだけ戻った場合は当日生成済みフラグを尊重する。
          ref.read(sentenceControllerProvider.notifier).loadOrGenerateToday(
                dailySentenceGenerated: false,
                generationParams: ref.read(generationParamsProvider),
              );
          ref.invalidate(allSentencesProvider);
        }
      });
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route == null || identical(route, _analyticsRoute)) return;
    final observer = ref.read(analyticsServiceProvider).observer;
    if (_analyticsRoute != null) observer.unsubscribe(this);
    _analyticsRoute = route;
    observer.subscribe(this, route);
  }

  @override
  void didPopNext() {
    // 詳細画面などから戻ったとき、root route の「/」ではなく現在のタブを送る。
    _logCurrentTabScreen();
  }

  @override
  void dispose() {
    _notificationOpenSubscription?.cancel();
    ref.read(analyticsServiceProvider).observer.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkAndReloadIfNeeded();
    }
  }

  /// 配信された今日の例文があれば表示する。表示したら true。
  Future<bool> _showDeliveredIfAny({String? sentenceId}) async {
    final delivered = await _dailySentenceService.sync(sentenceId: sentenceId);
    if (delivered == null || !mounted) return false;

    final current = ref.read(sentenceControllerProvider);
    if (current is SentenceStateSuccess &&
        current.sentence.id == delivered.id) {
      return true;
    }
    ref.read(sentenceControllerProvider.notifier).showSentence(delivered);
    ref.invalidate(allSentencesProvider);
    return true;
  }

  /// 初回ロードと通知タップ処理を直列化する。
  ///
  /// 並行させると sync() が二重に走り、通知経由で表示した配信例文を
  /// 初回ロード側の loadOrGenerateToday が上書きしてしまう。
  /// 初回起動時は onboarding の push 中に popUntil が走る危険もある。
  Future<void> _loadInitialSentenceThenHandleNotification() async {
    try {
      await _checkFirstLaunchAndLoadSentence();
    } finally {
      await _handleInitialNotificationOpen();
      await _maybeShowPremiumTrialStarted();
      await _maybeShowPremiumTrialEnded();
    }
  }

  /// 語彙測定を終えたオンボーディング末尾で、プレミアム体験の開始を伝える。
  ///
  /// 体験の起点はアカウント作成時なので、案内を出さないと本人は体験中だと
  /// 気づかないまま終わる。ここだけはプランへの導線も添える。何が使えるのかを
  /// 知った直後で、見たい人が自分で進める形にしておく（既定は「使ってみる」）。
  ///
  /// 一括配布向けの [_maybeShowPremiumTrialStarted] と同じフラグを立てて、
  /// 同じ案内が二度出ないようにする。
  Future<void> _showOnboardingTrialStarted() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(AppConfig.prefKeyPremiumTrialStartedNotified) ?? false) {
      return;
    }
    if (!mounted) return;

    // 体験の入口なので日数は規定値で固定して出す。期限は JST 0:00 に切り上がる
    // ので残りから数えると「3日間」に見えてしまい、告知した期間と食い違う。
    const days = premiumTrialDays;

    final analytics = ref.read(analyticsServiceProvider);
    unawaited(analytics.logPremiumTrialStarted(action: 'shown'));

    final openPaywall = await showPremiumTrialStartedDialog(
      context,
      days: days,
      offerPaywall: true,
    );
    unawaited(
      analytics.logPremiumTrialStarted(
        action: openPaywall ? 'accepted' : 'dismissed',
      ),
    );
    await prefs.setBool(AppConfig.prefKeyPremiumTrialStartedNotified, true);
    if (!openPaywall || !mounted) return;
    await PaywallBottomSheet.show(context, source: 'onboarding_trial_started');
  }

  /// 後から配られたプレミアム体験の開放を、最初の起動で一度だけ知らせる。
  ///
  /// 黙って配ると本人は増えたことに気づかず、終了ダイアログで初めて「失った」と
  /// 知らされる。それでは体験させたことにならないので、開放側にも案内を出す。
  ///
  /// 開放と終了が同じ起動で両方立つことはない（体験中は premium_trial_ended_at が
  /// まだ無く、終了後は premiumTrialActive が false になる）が、順序として
  /// 開放を先に呼ぶ。
  Future<void> _maybeShowPremiumTrialStarted() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(AppConfig.prefKeyPremiumTrialStartedNotified) ?? false) {
      return;
    }
    await ref.read(userDocProvider.future);
    if (!mounted) return;

    // 一括配布で配られた人だけが対象。
    if (ref.read(premiumTrialBackfilledAtProvider).valueOrNull == null) return;
    // 配布後に起動しないまま期限が切れた人には、開放を伝えても意味がない。
    // 何も持っていない状態で「開放しました」と言うことになる。
    if (!(ref.read(premiumTrialActiveProvider).valueOrNull ?? false)) return;

    if (ModalRoute.of(context)?.isCurrent != true) return;

    final expiresAt = ref.read(premiumTrialExpiresAtProvider).valueOrNull;
    if (expiresAt == null) return;
    unawaited(
      ref
          .read(analyticsServiceProvider)
          .logPremiumTrialStarted(action: 'shown'),
    );
    await showPremiumTrialStartedDialog(context, days: premiumTrialDays);
    await prefs.setBool(AppConfig.prefKeyPremiumTrialStartedNotified, true);
  }

  /// プレミアム体験が切れていたら、最初の起動で一度だけ知らせて登録へ誘導する。
  ///
  /// 黙って機能が減ると不具合に見えるので、終了そのものを伝えることが主目的。
  /// 表示できなかった場合はフラグを立てないので、次の起動で出し直される。
  ///
  /// 期限そのものではなく premium_trial_ended_at（期限切れ後の最初の日次リセットで
  /// dailyBatch が刻む）で判定する。期限切れ当日はまだ premium の回数が残っており、
  /// 何も失っていないうちに「終了しました」と言うと嘘になる。
  Future<void> _maybeShowPremiumTrialEnded() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(AppConfig.prefKeyPremiumTrialEndedNotified) ?? false) {
      return;
    }
    // users doc が届く前に読むと常に「判定不能」で素通りしてしまう。
    await ref.read(userDocProvider.future);
    if (!mounted) return;

    // トライアルを持たない旧ユーザーには出さない。
    if (ref.read(premiumTrialEndedAtProvider).valueOrNull == null) return;
    if (ref.read(effectivePremiumProvider)) return;

    if (ModalRoute.of(context)?.isCurrent != true) return;

    final analytics = ref.read(analyticsServiceProvider);
    unawaited(analytics.logPremiumTrialEnded(action: 'shown'));

    final openPaywall = await showPremiumTrialEndedDialog(context);
    unawaited(
      analytics.logPremiumTrialEnded(
        action: openPaywall ? 'accepted' : 'dismissed',
      ),
    );
    await prefs.setBool(AppConfig.prefKeyPremiumTrialEndedNotified, true);
    // 体験中に選んだテーマは free では効かない。表示と実際の生成を揃える。
    await ref
        .read(settingsControllerProvider.notifier)
        .setGenerationParam('topic', null);
    if (!openPaywall || !mounted) return;
    await PaywallBottomSheet.show(context, source: 'trial_ended');
  }

  /// 設定タブを開いたときに、通知の案内を出す。
  ///
  /// こちらから画面を動かして出すのはやめた。自分で設定を開いた人なら、
  /// 案内を閉じた先に通知のトグルが見えていて、後から切り替える場所も分かる。
  ///
  /// 例文を1つも学習していないうちは出さない。毎日届く価値が伝わる前に
  /// 聞くと断られる（iOSでは一度拒否されると二度と要求できない）。
  Future<void> _maybeShowNotificationCoachOnSettingsOpen() async {
    // 初期化前の state は「表示済み」側の既定値なので、読む前に必ず待つ。
    await ref.read(settingsControllerProvider.notifier).initialized;
    if (!mounted ||
        ref.read(settingsControllerProvider).notificationCoachShown) {
      return;
    }
    // 初回は例文が自動生成されるため、1つあるだけでは価値を体験したことに
    // ならない。2つ目まで進んだ人にだけ聞く。
    final sentences = await ref.read(allSentencesProvider.future);
    if (sentences.length < 2 || !mounted) return;
    // タブが描画されてから案内を重ねる。開いた直後に離れた人には出さない。
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (!mounted || _currentIndex != _settingsTabIndex) return;
    await _maybeShowNotificationCoach();
  }

  Future<void> _handleInitialNotificationOpen() async {
    final message = await FirebaseMessaging.instance.getInitialMessage();
    if (message != null) await _handleNotificationOpen(message);
  }

  /// 通知タップ時は配信例文を取得できた場合だけ画面を切り替える。
  /// 取得前に切り替えると、オフライン等で失敗したときにクイズの進行だけが失われる。
  Future<void> _handleNotificationOpen(RemoteMessage message) async {
    if (!_isDailySentenceNotification(message) || !mounted) return;
    final sentenceId = message.data['sentence_id']?.toString();
    final shown = await _showDeliveredIfAny(sentenceId: sentenceId);
    if (!shown || !mounted) return;
    _openLearningSentenceStage();
  }

  bool _isDailySentenceNotification(RemoteMessage message) {
    return message.data['type'] == 'daily_sentence';
  }

  void _openLearningSentenceStage() {
    Navigator.of(context).popUntil((route) => route.isFirst);
    if (_currentIndex != 0) {
      setState(() => _currentIndex = 0);
      _logCurrentTabScreen(index: 0);
    }
    _learningKey.currentState?.showSentenceStage();
  }

  /// 例文の価値を体験した後に一度だけ、毎日例文通知を継続サポート機能として紹介する。
  ///
  /// 体験する前に出すと通知そのものを断られやすい（iOSでは一度拒否されると
  /// 二度と要求できない）ため、インストール直後には出さない。
  /// 「通知をオンにする」を押したらその場でOSの許可要求まで出す。設定タブの
  /// トグルまで自分で辿らせていた頃は、承諾してもトークン登録まで届いていなかった。
  Future<void> _maybeShowNotificationCoach() async {
    final controller = ref.read(settingsControllerProvider.notifier);
    await controller.initialized;
    if (!mounted) return;

    final coachShown =
        ref.read(settingsControllerProvider).notificationCoachShown;
    final permissionGranted =
        await controller.hasProminentNotificationPermission();
    if (!shouldShowNotificationCoach(
      coachShown: coachShown,
      permissionGranted: permissionGranted,
    )) {
      // 許可済みだと確認できたときだけ、紹介不要として記録する。判定不能（null）
      // で記録すると、一度の取得失敗でそのユーザーが恒久的に案内対象から外れる。
      if (!coachShown && permissionGranted == true) {
        await controller.markNotificationCoachShown();
      }
      return;
    }
    // 前面に別の画面がある間は出さない。ここで出さなくても表示済みフラグは
    // 立たないため、次の起動で出し直される。
    if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;

    final analytics = ref.read(analyticsServiceProvider);
    unawaited(analytics.logNotificationCoach(action: 'shown'));

    final accepted = await showNotificationCoachDialog(context);
    unawaited(
      analytics.logNotificationCoach(
        action: accepted ? 'accepted' : 'dismissed',
      ),
    );
    // 出したら結果に関わらず記録する。断られた直後の出し直しは印象を悪くする。
    await controller.markNotificationCoachShown();
    if (!accepted || !mounted) return;

    // ここでOSの許可ダイアログが出る。答えるまで下の await は返らないため、
    // 要求に入ったこと自体を先に記録する。これが無いと「ダイアログを放置して
    // アプリを離れた」と「許可後の登録が終わらなかった」を後から区別できない。
    unawaited(analytics.logNotificationCoach(action: 'requesting'));
    final result = await controller.setDailyReminderEnabled(true);
    unawaited(
      analytics.logNotificationCoach(action: result?.name ?? 'denied'),
    );
    if (!mounted) return;
    // pending は許可が取れているので、登録待ちでも成功として伝える。
    // quiet（昇格を断られた）は「届きます」と言うと嘘になるので分ける。
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(switch (result) {
          PushEnableResult.denied =>
            L10n.of(context).settingsAllowNotificationInOsSettings,
          PushEnableResult.quiet => L10n.of(context).notifCoachStillQuiet,
          _ => L10n.of(context).notifCoachEnabled,
        }),
      ),
    );
  }

  /// アプリ復帰時にFirestoreフラグを確認し、未生成なら再ロード
  Future<void> _checkAndReloadIfNeeded() async {
    // 初回ロードが完了する前はスキップ（_checkFirstLaunchAndLoadSentenceとの二重生成を防ぐ）
    if (!_initialLoadCompleted) return;

    // 生成中ならスキップ
    final currentState = ref.read(sentenceControllerProvider);
    if (currentState is SentenceStateLoading) {
      return;
    }

    // 裏に回っている間に配信されていれば、それに差し替える
    if (await _showDeliveredIfAny()) return;

    final data = await ref.read(userDocProvider.future);
    final isGenerated = (data?['daily_sentence_generated'] as bool?) ?? false;

    // 今日の生成済みフラグが立っていて表示成功状態なら、そのまま維持する
    if (isGenerated && currentState is SentenceStateSuccess) {
      return;
    }

    if (!isGenerated) {
      ref.read(sentenceControllerProvider.notifier).loadOrGenerateToday(
            dailySentenceGenerated: false,
            generationParams: ref.read(generationParamsProvider),
          );
      ref.invalidate(allSentencesProvider);
    }
  }

  /// Check if first launch and load sentence
  Future<void> _checkFirstLaunchAndLoadSentence() async {
    // 設定の読み込み完了を待ってから判定する
    await ref.read(settingsControllerProvider.notifier).initialized;
    final isFirstLaunch = ref.read(isFirstLaunchProvider);

    if (isFirstLaunch) {
      if (mounted) {
        // まず機能紹介の3枚。何のアプリかを見せてから質問へ入る。
        await Navigator.push<void>(
          context,
          MaterialPageRoute(
            settings: const RouteSettings(name: OnboardingScreen.routeName),
            builder: (context) => OnboardingScreen(
              onComplete: () {
                Navigator.pop(context);
              },
            ),
          ),
        );
      }
      if (mounted) {
        // 続けてヒアリング。本人の状況を聞いてから説明書・語彙テストへ入る。
        await Navigator.push<void>(
          context,
          MaterialPageRoute(
            settings: const RouteSettings(name: InterviewScreen.routeName),
            builder: (context) => InterviewScreen(
              onComplete: () {
                Navigator.pop(context);
              },
            ),
          ),
        );
      }
      // 回答の送信は分析と毎日配信のため。テーマは端末側で決めるので、
      // 書き込みの着地は待たない。語彙スコアには効かないので、着地の順序が
      // 語彙テストと前後しても影響しない。
      unawaited(InterviewReporter().report());

      if (mounted) {
        // 先に使い方の説明書を先頭から読ませる。読みたくない人はスキップ
        // できる。語彙テストは「何を測るのか」が分かってからのほうが、
        // 意味の分からない4択を突然出されるより降りられにくい。
        await Navigator.push<void>(
          context,
          MaterialPageRoute(
            settings: const RouteSettings(name: GuideScreen.routeName),
            builder: (context) => GuideScreen(
              isFirstLaunch: true,
              onDone: () => Navigator.pop(context),
            ),
          ),
        );
      }

      // 最後に語彙テスト。生成の開始はこの後まで待つ。key_word は
      // estimated_vocab の帯から選ぶので、測る前に始めると初回の1文だけ
      // 0 語相当の難度で出てしまう。
      if (mounted) {
        await Navigator.push<void>(
          context,
          MaterialPageRoute(
            settings: const RouteSettings(name: VocabTestScreen.routeName),
            builder: (context) => VocabTestScreen(
              mandatory: true,
              source: 'onboarding',
              onFinished: (_) => Navigator.pop(context),
            ),
          ),
        );
      }

      // 測り終えた直後に、ここから体験が始まることを伝える。
      // 新規ユーザーの体験はアカウント作成時から動いているので、黙っていると
      // 「最初から多かった」としか映らず、終了時に失うものが結び付かない。
      if (mounted) {
        await _showOnboardingTrialStarted();
      }

      // 生成開始。ここから先は学習画面のローディングで待たせる。
      _initialLoadFuture ??= _applyInterviewTopicAndLoad(await _savedGoal());

      // 初回起動完了を記録
      ref.read(settingsControllerProvider.notifier).completeFirstLaunch();
    }

    if (!mounted) return;

    await (_initialLoadFuture ??= _loadTodaySentence());

    _initialLoadCompleted = true;

    if (!mounted) return;

    // 履歴を更新
    ref.invalidate(allSentencesProvider);
  }

  /// 端末に残っているヒアリングの用途（interview.goal）。未回答なら null。
  Future<String?> _savedGoal() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('${AppConfig.prefKeyInterviewPrefix}goal');
  }

  /// ヒアリングで申告した用途に関連するテーマを1つ引き、テーマ設定に入れてから
  /// 初回例文を生成する。
  ///
  /// 以後の変更は本人がテーマ選択UIでやる。ここで設定に入れておくと、次の
  /// テーマが画面に出るし、毎日配信（preferred_topic）にも同じテーマが乗る。
  /// テーマ選択の利用率を水増ししないよう、設定変更イベントは送らない。
  Future<void> _applyInterviewTopicAndLoad(String? goal) async {
    final topic = GenerationConstants.topicForInterviewGoal(goal);
    if (topic != null) {
      await ref
          .read(settingsControllerProvider.notifier)
          .setGenerationParam('topic', topic, logChange: false);
    }
    await _loadTodaySentence();
  }

  /// Firestoreフラグを取得し、未生成なら自動生成、済みなら最新を表示
  Future<void> _loadTodaySentence() async {
    // 配信例文の取り込みを先に終わらせる。今日ぶんがあればそれが今日の例文なので、
    // 生成もローカル読み込みも走らせない（通知タップかどうかの判定は不要）。
    if (await _showDeliveredIfAny()) return;

    final data = await ref.read(userDocProvider.future);
    final isGenerated = (data?['daily_sentence_generated'] as bool?) ?? false;
    await ref.read(sentenceControllerProvider.notifier).loadOrGenerateToday(
          dailySentenceGenerated: isGenerated,
          generationParams: ref.read(generationParamsProvider),
        );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final screens = [
      LearningScreen(key: _learningKey),
      const HistoryScreen(),
      const SettingsScreen(),
    ];

    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          // IndexedStack は他タブを破棄しないため、再生中の例文が
          // 鳴り続けてしまう。タブを離れたら明示的に止める。
          unawaited(ref.read(ttsServiceProvider).stopAll());
          setState(() {
            _currentIndex = index;
          });
          _logCurrentTabScreen(index: index);
          if (index == _settingsTabIndex) {
            unawaited(_maybeShowNotificationCoachOnSettingsOpen());
          }
        },
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.school_outlined),
            selectedIcon: const Icon(Icons.school),
            label: l10n.navLearn,
          ),
          NavigationDestination(
            icon: const Icon(Icons.history_outlined),
            selectedIcon: const Icon(Icons.history),
            label: l10n.navHistory,
          ),
          NavigationDestination(
            icon: const Icon(Icons.settings_outlined),
            selectedIcon: const Icon(Icons.settings),
            label: l10n.navSettings,
          ),
        ],
      ),
    );
  }

  void _logCurrentTabScreen({int? index}) {
    final currentIndex = index ?? _currentIndex;
    final screenName = switch (currentIndex) {
      0 => 'learning',
      1 => 'history',
      2 => 'settings',
      _ => 'home',
    };

    // IndexedStack は route が増えないため、タブ切り替えは手動で screen_view を送る。
    unawaited(
      ref.read(analyticsServiceProvider).logScreenView(
            screenName: screenName,
            screenClass: 'HomeTab',
          ),
    );
  }
}

enum _LearningStage { sentence, quiz, summaryQuiz }

@visibleForTesting
bool changedFromNoRemainingToAvailable(
  AsyncValue<int>? previous,
  AsyncValue<int> next,
) {
  final previousRemaining = previous?.valueOrNull;
  final nextRemaining = next.valueOrNull;
  return previousRemaining != null &&
      nextRemaining != null &&
      previousRemaining <= 0 &&
      nextRemaining > 0;
}

@visibleForTesting
bool shouldAutoLoadAfterSentenceQuotaRefresh({
  required AsyncValue<int>? previous,
  required AsyncValue<int> next,
  required bool dailySentenceGenerated,
}) {
  return !dailySentenceGenerated &&
      changedFromNoRemainingToAvailable(previous, next);
}

/// まとめクイズ（5問チャレンジ）を誘導する間隔（例文の本数）。
@visibleForTesting
const int summaryQuizThreshold = 5;

/// 確認クイズのサマリーでまとめクイズへ誘導するか。
///
/// completedCount は前回のまとめクイズ以降にこなした例文の本数（いま解いて
/// いる確認クイズの1本は含まない）。例文 summaryQuizThreshold 本ごとに出す。
///
/// 以前は初回だけ 1 本目で誘導していたが、使い始めの1本目に別のクイズを
/// 重ねるより、まず例文→確認クイズの一巡に慣れてもらうほうがよいのでやめた。
@visibleForTesting
bool shouldOfferSummaryQuiz(int completedCount) =>
    completedCount + 1 >= summaryQuizThreshold;

class LearningScreen extends ConsumerStatefulWidget {
  /// 初回の学習が一巡（まとめクイズ完了）した直後に呼ばれる。
  /// 通知の案内を出してよいタイミング（まとめクイズの結果／その見送り）。

  const LearningScreen({
    super.key,
  });

  @override
  ConsumerState<LearningScreen> createState() => _LearningScreenState();
}

class _LearningScreenState extends ConsumerState<LearningScreen> {
  static const String _completedCountKey = 'learning_completed_count';
  _LearningStage _stage = _LearningStage.sentence;
  ThaiSentence? _quizSentence;
  int _completedCount = 0;

  @override
  void initState() {
    super.initState();
    _loadCompletedCount();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _restoreSavedSummaryQuizIfNeeded();
      ref.listenManual(sentenceControllerProvider, (prev, next) {
        if (prev is SentenceStateLoading &&
            next is SentenceStateSuccess &&
            next.generated &&
            _stage == _LearningStage.sentence) {
          ref.read(quizControllerProvider.notifier).prepareQuiz(next.sentence);
        }
      });
    });
  }

  Future<void> _restoreSavedSummaryQuizIfNeeded() async {
    final quizNotifier = ref.read(quizControllerProvider.notifier);
    final hasSavedSummaryQuiz = await quizNotifier.hasSavedSummaryQuiz();
    if (!mounted || !hasSavedSummaryQuiz || _stage != _LearningStage.sentence) {
      return;
    }

    _setStage(_LearningStage.summaryQuiz);
    await quizNotifier.generateAndStartQuiz();
  }

  Future<void> _loadCompletedCount() async {
    final prefs = await SharedPreferences.getInstance();
    final count = prefs.getInt(_completedCountKey) ?? 0;
    if (mounted && count != _completedCount) {
      setState(() => _completedCount = count);
    }
  }

  Future<void> _setCompletedCount(int count) async {
    _completedCount = count;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_completedCountKey, count);
  }

  void _setStage(_LearningStage newStage) {
    setState(() => _stage = newStage);
  }

  void _returnToLearningTop() {
    final sentence = _quizSentence;
    if (sentence != null) {
      ref.read(sentenceControllerProvider.notifier).showSentence(sentence);
    }
    _setStage(_LearningStage.sentence);
  }

  void showSentenceStage() {
    _quizSentence = null;
    ref.read(quizControllerProvider.notifier).reset();
    _setStage(_LearningStage.sentence);
  }

  /// 次の例文へ進む。テーマの適用可否・トライアル消費は controller 側で判定する。
  Future<void> _proceedToNextSentence() async {
    await _generateNextLearningSentence();
  }

  Future<void> _generateNextLearningSentence() async {
    _setStage(_LearningStage.sentence);
    final genParams = ref.read(generationParamsProvider);
    await ref.read(sentenceControllerProvider.notifier).generateSentence(
          generationParams: genParams,
        );
    final sentenceState = ref.read(sentenceControllerProvider);
    if (sentenceState is SentenceStateSuccess) {
      ref
          .read(quizControllerProvider.notifier)
          .prepareQuiz(sentenceState.sentence);
      ref.invalidate(allSentencesProvider);
      unawaited(_requestReviewAfterSentenceGenerated());
    }
  }

  /// 例文が出た直後は満足度が高い。クイズまで進まない層への唯一の依頼機会
  /// なので、生成の完了を待ってから静かに出す。
  Future<void> _requestReviewAfterSentenceGenerated() async {
    await Future<void>.delayed(const Duration(seconds: 2));
    if (!mounted ||
        ref.read(sentenceControllerProvider) is! SentenceStateSuccess) {
      return;
    }
    final outcome = await ref
        .read(reviewPromptServiceProvider)
        .maybeRequestAfterSentenceGenerated();
    unawaited(
      ref.read(analyticsServiceProvider).logReviewPrompt(
            source: 'sentence',
            outcome: outcome.name,
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    ref.listen(remainingSentencesProvider, (prev, next) {
      if (changedFromNoRemainingToAvailable(prev, next) &&
          mounted &&
          _stage != _LearningStage.sentence) {
        _setStage(_LearningStage.sentence);
      }
    });

    // この確認クイズのサマリーでまとめクイズへ誘導するか。
    final offerSummaryQuiz = shouldOfferSummaryQuiz(_completedCount);

    return switch (_stage) {
      _LearningStage.sentence => TodayScreen(
          onStartQuiz: (sentence, offerSource) {
            _quizSentence = sentence;
            final quizNotifier = ref.read(quizControllerProvider.notifier);
            final quizState = ref.read(quizControllerProvider);

            // 既に回答中/結果表示中ならそのまま再表示
            if (quizState is QuizAnswering || quizState is QuizShowResult) {
              // nothing
            } else {
              quizNotifier.startLearningQuiz(
                sentence,
                offerSource: offerSource,
              );
            }
            _setStage(_LearningStage.quiz);
          },
        ),
      _LearningStage.quiz => Scaffold(
          appBar: AppBar(
            title: Text(l10n.navLearn),
            automaticallyImplyLeading: false,
            actions: const [QuizProgressCounter()],
          ),
          body: QuizScreen(
            showAppBar: false,
            title: l10n.learnQuizTitle,
            learningSentence: _quizSentence,
            onBackToLearningStart: _returnToLearningTop,
            nextButtonLabel: l10n.learnNextSentence,
            onOptionalChallenge: offerSummaryQuiz
                ? () async {
                    await _setCompletedCount(0);
                    ref.read(quizControllerProvider.notifier).reset();
                    ref
                        .read(quizControllerProvider.notifier)
                        .generateAndStartQuiz();
                    _setStage(_LearningStage.summaryQuiz);
                  }
                : null,
            onNextSentence: () async {
              await _setCompletedCount(_completedCount + 1);
              await _proceedToNextSentence();
            },
          ),
        ),
      _LearningStage.summaryQuiz => Scaffold(
          appBar: AppBar(
            title: Text(l10n.learnSummaryQuizTitle),
            automaticallyImplyLeading: false,
            actions: const [QuizProgressCounter()],
          ),
          body: QuizScreen(
            showAppBar: false,
            title: l10n.learnSummaryQuizTitle,
            showVocabScoreTransition: true,
            onNextSentence: () async {
              await _setCompletedCount(0);
              await _proceedToNextSentence();
            },
          ),
        ),
    };
  }
}

typedef LearningQuizStartCallback = void Function(
  ThaiSentence sentence,
  String? offerSource,
);

/// Today's sentence screen
class TodayScreen extends ConsumerStatefulWidget {
  final LearningQuizStartCallback? onStartQuiz;

  const TodayScreen({
    super.key,
    this.onStartQuiz,
  });

  /// デフォルトの挨拶例文（サンプル、履歴には保存されない）。
  /// 訳・品詞・文脈は表示用の文言なので言語に追従させる。
  static ThaiSentence defaultGreetingSentence(L10n l10n) => ThaiSentence(
        id: null, // idがnullなのでDBには保存されない
        thaiText: 'สวัสดีครับ',
        pronunciation: 'sawatdii khrap',
        japaneseTranslation: l10n.sampleGreetingTranslation,
        wordBreakdowns: [
          WordBreakdown(
            wordText: 'สวัสดี',
            pronunciation: 'sà-wàt-dii',
            meaning: l10n.sampleGreetingWord1Meaning,
            grammaticalRole: l10n.sampleGreetingWord1Role,
            wordOrder: 0,
            syllables: [
              Syllable(
                text: 'สวัส',
                initialConsonant: 'สว',
                consonantClass: 'high',
                tone: 'low',
                toneMark: 'none',
                syllableType: 'dead',
              ),
              Syllable(
                text: 'ดี',
                initialConsonant: 'ด',
                consonantClass: 'middle',
                tone: 'mid',
                toneMark: 'none',
                syllableType: 'live',
              ),
            ],
          ),
          WordBreakdown(
            wordText: 'ครับ',
            pronunciation: 'khráp',
            meaning: l10n.sampleGreetingWord2Meaning,
            grammaticalRole: l10n.sampleGreetingWord2Role,
            wordOrder: 1,
            syllables: [
              Syllable(
                text: 'ครับ',
                initialConsonant: 'คร',
                consonantClass: 'low',
                tone: 'high',
                toneMark: 'none',
                syllableType: 'dead',
                hasShortVowel: true,
              ),
            ],
          ),
        ],
        context: SentenceContext(
          topic: l10n.sampleGreetingTopic,
          style: l10n.sampleGreetingStyle,
          emotion: l10n.sampleGreetingEmotion,
          usageScenarios: l10n.sampleGreetingUsage,
        ),
        createdAt: null,
        generationTier: 'free',
      );

  @override
  ConsumerState<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends ConsumerState<TodayScreen> {
  /// 「確認クイズへ」ボタンの位置特定用（導線が画面内にあるかの判定に使う）。
  final GlobalKey _quizButtonKey = GlobalKey();
  final GlobalKey _sentenceScrollViewportKey = GlobalKey();
  final ScrollController _sentenceScrollController = ScrollController();
  final Set<String> _scheduledQuizOfferShown = {};
  final Set<String> _loggedQuizOfferShown = {};
  final Set<String> _handledQuizOfferTaps = {};
  bool _quizOfferAssignmentHandled = false;

  /// 上限到達時のペイウォール導線の shown を二重に送らないためのフラグ。
  /// build はエラー表示のまま何度も走るので、State の生存期間中1回に絞る。
  bool _quotaPaywallImpressionLogged = false;

  @override
  void initState() {
    super.initState();
    _sentenceScrollController.addListener(_maybeLogVisibleQuizOffer);
  }

  @override
  void dispose() {
    _sentenceScrollController
      ..removeListener(_maybeLogVisibleQuizOffer)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(vocabStatsProvider, (prev, next) {
      final prevVocab = prev?.valueOrNull?.estimatedVocab ?? 0;
      final nextVocab = next.valueOrNull?.estimatedVocab ?? 0;
      if (nextVocab > prevVocab) {
        _checkLevelUp(nextVocab);
      }
    });
    final sentenceState = ref.watch(sentenceControllerProvider);
    final quizOfferVariant = ref.watch(quizOfferVariantProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        titleSpacing: AppConfig.screenPadding,
        // ボトムナビと同じ「学習」を繰り返さない。中身を名乗る。
        title: Text(
          L10n.of(context).learnAppBarTitle,
          style: Theme.of(context).appBarTheme.titleTextStyle?.copyWith(
                fontSize: 21,
                letterSpacing: 0.02 * 21,
              ),
        ),
        actions: [
          _buildVocabScoreChip(context),
          const SizedBox(width: AppConfig.screenPadding),
        ],
      ),
      body: _buildSentenceContent(
        context,
        sentenceState,
        quizOfferVariant,
      ),
    );
  }

  /// ヘッダー右の語彙スコア。学習の手応えを常に見える場所に置く。
  /// 内訳は設定画面の語彙スコアカードで見せるので、ここは表示だけ。
  Widget _buildVocabScoreChip(BuildContext context) {
    final stats = ref.watch(vocabStatsProvider).valueOrNull;
    if (stats == null) return const SizedBox.shrink();

    final isPremium = ref.watch(effectivePremiumProvider);
    final vocab = isPremium
        ? stats.estimatedVocab
        : stats.estimatedVocab.clamp(0, freeVocabScoreLimit).toInt();
    final levelId = vocabLevel(vocab);
    final level = vocabLevelLabel(L10n.of(context), levelId);
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 13),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(vocabLevelIcon(levelId), size: 15, color: AppColors.gold),
          const SizedBox(width: 7),
          Text(
            L10n.of(context).vocabWords(vocab),
            style: textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            level,
            style: textTheme.labelSmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  /// Build sentence content based on state
  Widget _buildSentenceContent(
    BuildContext context,
    SentenceState state,
    QuizOfferVariant? quizOfferVariant,
  ) {
    if (state is SentenceStateLoading) {
      return _buildLoadingState();
    } else if (state is SentenceStateSuccess) {
      return _buildSuccessState(
        context,
        state.sentence,
        quizOfferVariant,
      );
    } else if (state is SentenceStateError) {
      return _buildErrorState(context, state.message);
    } else if (state is SentenceStateEmpty) {
      return _buildEmptyState(context);
    } else {
      return _buildEmptyState(context);
    }
  }

  /// Build loading state
  Widget _buildLoadingState() {
    return LoadingCard(message: L10n.of(context).sentencePreparing);
  }

  /// Build success state with single sentence
  Widget _buildSuccessState(
    BuildContext context,
    ThaiSentence sentence,
    QuizOfferVariant? quizOfferVariant,
  ) {
    if (quizOfferVariant != null && quizOfferVariant.participatesInExperiment) {
      _scheduleQuizOfferShown(sentence, quizOfferVariant);
    }

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            key: _sentenceScrollViewportKey,
            controller: _sentenceScrollController,
            padding: const EdgeInsets.fromLTRB(
              AppConfig.screenPadding,
              AppConfig.defaultPadding,
              AppConfig.screenPadding,
              AppConfig.screenPadding,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SignInReminderBanner(),
                // 並びはモックのとおり。次に届くテーマ → 例文 → 聞く/話す →
                // 学習単語。例文を先に読ませ、そのあとで単語を確かめる。
                const NextSentenceTopicLabel(
                  paywallSource: 'learn_next_topic',
                  banner: true,
                ),
                const SizedBox(height: 14),
                _buildSentenceCard(context, sentence),
                // 聞くは例文の付属。ここだけ詰めて1組に見せる。
                const SizedBox(height: 8),
                SentenceAudioSection(
                  sentence: sentence,
                  analyticsSource: 'today_sentence',
                  practiceScope: 'home_card',
                  // 発音練習は詳細画面だけに置く。学習タブは
                  // 読む → 覚えたか確認 の一本道に保つ。
                  showPractice: false,
                ),
                // ここで組が変わる（読む → 覚える）。上の間隔より広く取る。
                // ボタン自身が上下に余白を持つので、見た目の差は数値より開く。
                const SizedBox(height: 14),
                _buildTargetWordsSection(context, sentence),
                // 導線は学習単語のすぐ下に置く。「この単語を覚える → 確認する」
                // が一続きに見える距離で、別セクションには見せない。
                if (quizOfferVariant != null) ...[
                  const SizedBox(height: 12),
                  QuizOffer(
                    variant: quizOfferVariant,
                    targetKey: _quizButtonKey,
                    onPressed: () =>
                        _handleQuizOfferTap(sentence, quizOfferVariant),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _quizOfferEventKey(
    ThaiSentence sentence,
    QuizOfferVariant variant,
  ) {
    final sentenceKey = sentence.id ??
        '${sentence.thaiText}|${sentence.createdAt?.millisecondsSinceEpoch}';
    return '$sentenceKey|${variant.analyticsSource}';
  }

  void _scheduleQuizOfferShown(
    ThaiSentence sentence,
    QuizOfferVariant variant,
  ) {
    final eventKey = _quizOfferEventKey(sentence, variant);
    if (_loggedQuizOfferShown.contains(eventKey) ||
        !_scheduledQuizOfferShown.add(eventKey)) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _scheduledQuizOfferShown.remove(eventKey);
      if (!mounted) return;

      final currentState = ref.read(sentenceControllerProvider);
      final currentVariant = ref.read(quizOfferVariantProvider).valueOrNull;
      if (currentState is! SentenceStateSuccess ||
          currentVariant != variant ||
          _quizOfferEventKey(currentState.sentence, variant) != eventKey) {
        return;
      }

      await _logQuizOfferAssignmentOnce(variant);
      if (!mounted) return;

      _logQuizOfferShownIfVisible(eventKey, variant);
    });
  }

  Future<void> _logQuizOfferAssignmentOnce(QuizOfferVariant variant) async {
    if (_quizOfferAssignmentHandled) return;
    _quizOfferAssignmentHandled = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      final loggedSource =
          prefs.getString(AppConfig.prefKeyQuizOfferAssignmentLoggedV1);
      if (loggedSource == variant.analyticsSource) return;

      unawaited(
        ref.read(analyticsServiceProvider).logQuizOffer(
              action: 'assigned',
              source: variant.analyticsSource,
            ),
      );
      unawaited(
        prefs.setString(
          AppConfig.prefKeyQuizOfferAssignmentLoggedV1,
          variant.analyticsSource,
        ),
      );
    } catch (_) {
      // 保存領域が使えなくても、この画面ライフサイクル中は上のboolで一度に抑える。
      unawaited(
        ref.read(analyticsServiceProvider).logQuizOffer(
              action: 'assigned',
              source: variant.analyticsSource,
            ),
      );
    }
  }

  void _maybeLogVisibleQuizOffer() {
    if (!mounted) return;
    final sentenceState = ref.read(sentenceControllerProvider);
    final variant = ref.read(quizOfferVariantProvider).valueOrNull;
    if (sentenceState is! SentenceStateSuccess || variant == null) return;

    _logQuizOfferShownIfVisible(
      _quizOfferEventKey(sentenceState.sentence, variant),
      variant,
    );
  }

  void _logQuizOfferShownIfVisible(
    String eventKey,
    QuizOfferVariant variant,
  ) {
    if (_loggedQuizOfferShown.contains(eventKey) ||
        !_isQuizOfferVisible(variant)) {
      return;
    }
    _loggedQuizOfferShown.add(eventKey);

    unawaited(
      ref.read(analyticsServiceProvider).logQuizOffer(
            action: 'shown',
            source: variant.analyticsSource,
          ),
    );
  }

  bool _isQuizOfferVisible(QuizOfferVariant variant) {
    final targetContext = _quizButtonKey.currentContext;
    final targetBox = targetContext?.findRenderObject() as RenderBox?;
    if (targetContext == null ||
        !targetContext.mounted ||
        !TickerMode.getValuesNotifier(targetContext).value.enabled ||
        ModalRoute.of(context)?.isCurrent != true ||
        targetBox == null ||
        !targetBox.hasSize) {
      return false;
    }

    // 導線は学習単語の直下に必ず描画するので、描画済みなら可視とみなす。
    return true;
  }

  void _handleQuizOfferTap(
    ThaiSentence sentence,
    QuizOfferVariant variant,
  ) {
    if (variant.participatesInExperiment) {
      final eventKey = _quizOfferEventKey(sentence, variant);
      if (!_handledQuizOfferTaps.add(eventKey)) return;

      unawaited(
        ref.read(analyticsServiceProvider).logQuizOffer(
              action: 'tapped',
              source: variant.analyticsSource,
            ),
      );
    }
    widget.onStartQuiz?.call(
      sentence,
      variant.participatesInExperiment ? variant.analyticsSource : null,
    );
  }

  Widget _buildTargetWordsSection(
    BuildContext context,
    ThaiSentence sentence,
  ) {
    final targetWords = sentence.targetWords;
    if (targetWords == null || targetWords.isEmpty) {
      return const SizedBox.shrink();
    }

    final breakdownMap = {
      for (final wb in sentence.wordBreakdowns) wb.wordText: wb,
    };

    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 見出しは字だけだと本文に埋もれるので、右へ罫線を伸ばして区切る。
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: [
              Text(
                L10n.of(context).todaysWords(targetWords.length),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.08 * 12,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(child: Divider(color: cs.outlineVariant, height: 1)),
            ],
          ),
        ),
        ...targetWords.map((word) {
          final wb = breakdownMap[word] ??
              breakdownMap['$wordๆ'] ??
              (word.endsWith('ๆ')
                  ? breakdownMap[word.replaceAll('ๆ', '')]
                  : null);
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            // 面はテーマの Card（白＋1px罫線）に任せる。塗り分けると
            // 例文カードの深藍と競って、どちらが主役か分からなくなる。
            child: Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                word,
                                // タイ文字は bold だと声調記号が潰れる。
                                // 色は読みと揃える。例文カードの金と同じ語だと
                                // 一目で結び付く。
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontSize: 19,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.goldInk,
                                ),
                              ),
                              if (wb != null) ...[
                                const SizedBox(width: 9),
                                Text(
                                  wb.pronunciation,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: AppColors.goldInk,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ],
                            ],
                          ),
                          if (wb != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              wb.meaning,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (wb != null)
                      // 44px の丸を敷いて、押せる場所と大きさを見せる。
                      IconButton(
                        icon: const Icon(Icons.volume_up_outlined, size: 20),
                        onPressed: () {
                          ref.read(ttsServiceProvider).speak(word);
                        },
                        style: IconButton.styleFrom(
                          backgroundColor: cs.surfaceContainerHigh,
                          foregroundColor: cs.primary,
                          minimumSize: const Size.square(
                            AppConfig.minTapTarget,
                          ),
                        ),
                        tooltip: L10n.of(context).playPronunciation,
                      ),
                  ],
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  /// Build a sentence card (shared between single and batch views)
  Widget _buildSentenceCard(
    BuildContext context,
    ThaiSentence sentence,
  ) {
    final borderRadius = BorderRadius.circular(AppConfig.heroBorderRadius);
    // カードの中身（再生ボタン・シークバー・ティアバッジ）は ColorScheme から
    // 色を引くので、面を深藍にする代わりにスキームごと差し替える。
    // 各ウィジェットに「濃い面の上か」を渡して回らずに済む。
    return Theme(
      data: Theme.of(context).copyWith(colorScheme: AppColors.onIndigo),
      child: Builder(
          builder: (context) => _buildSentenceCardBody(
                context,
                sentence,
                borderRadius: borderRadius,
              )),
    );
  }

  Widget _buildSentenceCardBody(
    BuildContext context,
    ThaiSentence sentence, {
    required BorderRadius borderRadius,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      color: AppColors.indigo,
      shape: RoundedRectangleBorder(borderRadius: borderRadius),
      child: Stack(
        children: [
          InkWell(
            onTap: () async {
              // 遷移してもこのカードは破棄されない。詳細画面のプレイヤーと
              // TTSを奪い合わないよう、ここで再生を止めておく。
              unawaited(ref.read(ttsServiceProvider).stopAll());
              await Navigator.push(
                context,
                MaterialPageRoute(
                  settings: const RouteSettings(name: DetailScreen.routeName),
                  builder: (context) => DetailScreen(
                    sentence: sentence,
                    source: 'today',
                  ),
                ),
              );
            },
            borderRadius: borderRadius,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppConfig.defaultPadding * 1.5,
                AppConfig.defaultPadding * 2.5,
                AppConfig.defaultPadding * 1.5,
                AppConfig.defaultPadding * 1.5,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    buildHighlightedThaiText(
                      sentence.thaiText,
                      sentence.targetWords ?? [],
                      Theme.of(context).textTheme.headlineMedium?.copyWith(
                                color: cs.onSurface,
                                fontWeight: FontWeight.w500,
                                height: 1.5,
                                fontSize: 32,
                              ) ??
                          TextStyle(fontSize: 32, color: cs.onSurface),
                      cs.primary,
                      words: sentence.wordBreakdowns,
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Pronunciation
                  Text.rich(
                    buildHighlightedPronunciation(
                      sentence,
                      Theme.of(context).textTheme.bodyLarge?.copyWith(
                                color: cs.onSurfaceVariant,
                                fontStyle: FontStyle.italic,
                              ) ??
                          TextStyle(
                            color: cs.onSurfaceVariant,
                            fontStyle: FontStyle.italic,
                          ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  // 金の細罫。タイ語と訳文のあいだに一本だけ引いて面を分ける。
                  Container(
                    height: 1,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppColors.gold,
                          AppColors.gold.withValues(alpha: 0),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    sentence.japaneseTranslation,
                    style: Theme.of(context)
                        .textTheme
                        .bodyLarge
                        ?.copyWith(color: cs.onSurface),
                  ),
                  const SizedBox(height: 14),
                  // カードの足元。テーマ・お気に入り・詳細への続きを1行にまとめる。
                  Row(
                    children: [
                      if (sentence.context?.topic != null)
                        _buildSentenceTopicTag(context, sentence),
                      const Spacer(),
                      _buildFavoriteButton(context, sentence),
                      // 「>」だけだと何へ続くのか読めない。語を添える。
                      Text(
                        L10n.of(context).learnOpenDetail,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant.withValues(alpha: 0.85),
                            ),
                      ),
                      const SizedBox(width: 3),
                      Icon(
                        Icons.chevron_right,
                        size: 18,
                        color: cs.onSurfaceVariant.withValues(alpha: 0.85),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            top: 14,
            right: 16,
            child: _buildSentenceTierBadge(context, sentence),
          ),
        ],
      ),
    );
  }

  /// カード足元のお気に入り。タップ領域は 44px。
  Widget _buildFavoriteButton(BuildContext context, ThaiSentence sentence) {
    if (sentence.id == null) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () async {
        await ref
            .read(sentenceRepositoryProvider)
            .toggleFavorite(sentence.id!, !sentence.isFavorite);
        final updated = sentence.copyWith(isFavorite: !sentence.isFavorite);
        ref.read(sentenceControllerProvider.notifier).showSentence(updated);
      },
      child: SizedBox(
        width: AppConfig.minTapTarget,
        height: AppConfig.minTapTarget,
        child: Icon(
          sentence.isFavorite ? Icons.favorite : Icons.favorite_border,
          size: 24,
          color: sentence.isFavorite
              ? AppColors.vermilion
              : cs.onSurfaceVariant.withValues(alpha: 0.8),
        ),
      ),
    );
  }

  /// カード足元のテーマタグ。この例文がどの場面のものかを示す。
  Widget _buildSentenceTopicTag(BuildContext context, ThaiSentence sentence) {
    final cs = Theme.of(context).colorScheme;
    final label = topicShortLabel(L10n.of(context), sentence.context?.topic);
    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.sell_outlined, size: 14, color: AppColors.gold),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _buildSentenceTierBadge(
    BuildContext context,
    ThaiSentence sentence,
  ) {
    final cs = Theme.of(context).colorScheme;
    final hasStoredTier = sentence.generationTier != null;
    final showPremium = hasStoredTier
        ? sentence.wasGeneratedWithPremiumSpec
        : _legacySentenceLooksPremium();
    final foreground = cs.onSurfaceVariant;


    return Tooltip(
      message: showPremium
          ? L10n.of(context).badgePremiumSentence
          : L10n.of(context).badgeFreeSentence,
      // カードの角に食い込ませると角丸が欠けて見える。内側のピルにする。
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 4, 10, 4),
        decoration: BoxDecoration(
          color: Colors.transparent,
          border: Border.all(
            color: showPremium
                ? AppColors.gold.withValues(alpha: 0.45)
                : cs.outlineVariant.withValues(alpha: 0.55),
          ),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          showPremium ? 'PREMIUM' : 'FREE',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontSize: 10,
                letterSpacing: 0.6,
                color: showPremium
                    ? AppColors.gold
                    : foreground.withValues(alpha: 0.82),
                fontWeight: FontWeight.w700,
              ),
        ),
      ),
    );
  }

  bool _legacySentenceLooksPremium() {
    // 体験中も premium スペックで生成しているので premium 表示にする。
    return ref.watch(effectivePremiumProvider);
  }

  static const _levelThresholds = [100, 300, 600, 1500];
  static const _prefKeyLastLevel = 'last_vocab_level';

  String _vocabLevel(int vocab) => vocabLevel(vocab);

  Future<void> _checkLevelUp(int vocab) async {
    final crossedThreshold = _levelThresholds.any((t) => vocab >= t);
    if (!crossedThreshold) return;

    final level = _vocabLevel(vocab);
    final prefs = await SharedPreferences.getInstance();
    final lastLevel = prefs.getString(_prefKeyLastLevel) ?? '入門';

    if (level == lastLevel) return;

    // レベルが上がった場合のみ（下がった場合は無視）
    final lastIndex =
        _levelThresholds.indexWhere((t) => t > (_thresholdForLevel(lastLevel)));
    final newIndex =
        _levelThresholds.indexWhere((t) => t > (_thresholdForLevel(level)));
    final effectiveLastIndex =
        lastIndex == -1 ? _levelThresholds.length : lastIndex;
    final effectiveNewIndex =
        newIndex == -1 ? _levelThresholds.length : newIndex;
    if (effectiveNewIndex <= effectiveLastIndex) return;

    await prefs.setString(_prefKeyLastLevel, level);
  }

  int _thresholdForLevel(String level) {
    switch (level) {
      case '入門':
        return 0;
      case '初級':
        return 100;
      case '初中級':
        return 300;
      case '中級':
        return 600;
      case '上級':
        return 1500;
      default:
        return 0;
    }
  }

  /// Build error state
  Widget _buildErrorState(BuildContext context, String message) {
    final isQuotaError = isQuotaErrorMessage(message);

    // 上限に当たった free だけがアップグレードで解ける状態にある。
    // 判定が付くまで（loading）は出さない。
    final plan = ref.watch(planStatusProvider).valueOrNull;
    final showUpgrade = isQuotaError && plan == PlanStatus.free;

    if (showUpgrade && !_quotaPaywallImpressionLogged) {
      _quotaPaywallImpressionLogged = true;
      unawaited(
        ref.read(analyticsServiceProvider).logPaywallBanner(
              action: 'shown',
              source: _quotaPaywallSource,
            ),
      );
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppConfig.defaultPadding * 2),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isQuotaError ? Icons.lock_outline : Icons.error_outline,
              size: 64,
              color: isQuotaError
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 24),
            Text(
              message,
              style: Theme.of(context).textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
            if (isQuotaError) ...[
              const SizedBox(height: 12),
              Text(
                nextResetText(L10n.of(context)),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.64),
                    ),
                textAlign: TextAlign.center,
              ),
            ],
            // 上限に当たった瞬間は「なぜ premium が要るのか」が最も伝わる場面
            // なので、ここでだけ割り込みなしに訴求する。free 5 に対して
            // premium 20（2026-08-25 に 10→20）と差が付いたため噛み合う。
            // premium で使い切った人には勧める先が無いので出さない。
            if (showUpgrade) ...[
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => PaywallBottomSheet.show(
                  context,
                  source: _quotaPaywallSource,
                ),
                icon: const Icon(Icons.lock_open),
                label: Text(
                  L10n.of(context)
                      .quotaSentenceUpgradeCta(premiumDailySentences),
                ),
              ),
            ],
            if (!isQuotaError) ...[
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () {
                  final genParams = ref.read(generationParamsProvider);
                  ref
                      .read(sentenceControllerProvider.notifier)
                      .generateSentence(generationParams: genParams);
                },
                icon: const Icon(Icons.refresh),
                label: Text(L10n.of(context).commonRetry),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Build empty state with default greeting sentence
  Widget _buildEmptyState(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppConfig.defaultPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // サンプル例文のラベル
          Card(
            color: Theme.of(context).colorScheme.secondaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(AppConfig.defaultPadding),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 20,
                    color: Theme.of(context).colorScheme.onSecondaryContainer,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      L10n.of(context).sampleSentenceNotice,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSecondaryContainer,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _buildSentenceCard(
            context,
            TodayScreen.defaultGreetingSentence(L10n.of(context)),
          ),
        ],
      ),
    );
  }
}
