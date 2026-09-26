import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/config/app_config.dart';
import '../../core/constants/generation_constants.dart';
import '../../l10n/app_localizations.dart';
import '../../data/models/thai_sentence.dart';
import '../../services/app_version_reporter.dart';
import '../../services/daily_sentence_service.dart';
import '../../services/interview_reporter.dart';
import '../../services/push_notification_service.dart';
import '../../services/sentence_view_marker.dart';
import '../providers/daily_set_provider.dart';
import '../providers/analytics_provider.dart';
import '../providers/sentence_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/subscription_provider.dart';
import '../providers/tts_provider.dart';
import '../providers/remaining_quota_provider.dart';
import '../widgets/notification_coach_dialog.dart';
import '../widgets/premium_lifetime_migration_dialog.dart';
import '../widgets/premium_trial_ended_dialog.dart';
import '../widgets/premium_trial_started_dialog.dart';
import 'history_screen.dart';
import 'interview_screen.dart';
import 'onboarding_screen.dart';
import 'vocab_test_screen.dart';
import 'guide_screen.dart';
import 'paywall_screen.dart';
import 'learning_screen.dart';
import 'settings_screen.dart';

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
  final _learningKey = GlobalKey<LearningScreenState>();
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
      // 通信できずに端末へ溜まった既読を流す。
      unawaited(SentenceViewMarker.instance.flush());
      _notificationOpenSubscription =
          FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationOpen);
      // 後ろで取り込んだ別端末の進行位置を、例文を読んでいる間だけ反映する。
      ref.listenManual(dailySetProvider, (previous, next) {
        if (!_initialLoadCompleted) return;
        final current = next.current;
        if (current == null || current.id == previous?.current?.id) return;
        _showIfNotVisible(current);
      });
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
          hasActiveSet: ref.read(dailySetProvider).isActive,
        )) {
          // dailyBatchリセット時は、進行中セットが無い場合だけ新日の例文を生成。
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

  /// 配信された今日の例文を取り込む。
  ///
  /// 複数日ぶん溜まっていても取りこぼさない。結果は取り込んだ全セットの
  /// 論理和で返す（[DeliveredOutcome] を参照）。
  Future<DeliveredOutcome> _showDeliveredIfAny({
    String? sentenceId,
    bool force = false,
  }) async {
    // 再インストール直後など端末が空なら、自分で生成した例文も戻す。
    final (deliveredSets, restored) = await (
      _dailySentenceService.syncAll(sentenceId: sentenceId),
      _dailySentenceService.restoreHistoryIfEmpty(),
    ).wait;
    if (restored > 0 && mounted) ref.invalidate(allSentencesProvider);
    var result = noDelivery;
    for (final delivered in deliveredSets) {
      if (!mounted) break;
      result = mergeDeliveredOutcome(
        result,
        await _acceptDeliveredSet(delivered, force: force),
      );
    }
    return result;
  }

  Future<DeliveredOutcome> _acceptDeliveredSet(
    DailySentenceSet delivered, {
    bool force = false,
  }) async {
    final activeSet = ref.read(dailySetProvider);
    // 同じ通知をもう一度開いても、途中まで進めたカーソルを先頭へ戻さない。
    if (isSameDailySet(activeSet, delivered)) {
      return (
        displayed: _showIfNotVisible(activeSet.current!, force: force),
        imported: true,
      );
    }

    // フォアグラウンド復帰と通知タップは同時に走りうる。進行中セットを新着で
    // 上書きすると、残りの例文が履歴にしか残らず「飛ばされた」ように見えるため、
    // 消化中なら次のセットとして永続化し、表示は奪わない。
    final queued = activeSet.isActive;
    final accepted =
        await ref.read(dailySetProvider.notifier).acceptDeliveredSet(
              setId: delivered.setId,
              sentences: delivered.sentences,
            );
    // 断られたもの（古い通知の再タップ）を表示すると、終わったセットの例文が
    // 復活する。待機列へ回したぶんは「取り込んだ」として数える。
    if (!mounted || !accepted) {
      return (displayed: false, imported: queued);
    }
    final shown = ref.read(dailySetProvider).current ?? delivered.first;
    return (
      displayed: _showIfNotVisible(shown, force: force),
      imported: true,
    );
  }

  /// 表示中の例文と違うときだけ差し替える。同じものを入れ直すと画面が瞬く。
  ///
  /// クイズを解いている最中は差し替えない。裏の例文だけ変わると、いま答えて
  /// いる問題と本文がずれる。通知タップのように本人が開いたとき（force）だけ
  /// 例文ステージへ戻して差し替える。
  ///
  /// 戻り値は、その例文が画面に出ているか。差し替えを見送ったのに「出した」と
  /// 答えると、呼び出し側は何も表示されていない画面のまま先へ進んでしまう。
  bool _showIfNotVisible(ThaiSentence sentence, {bool force = false}) {
    if (!force && !(_learningKey.currentState?.isOnSentenceStage ?? true)) {
      return false;
    }
    final current = ref.read(sentenceControllerProvider);
    if (current is SentenceStateSuccess && current.sentence.id == sentence.id) {
      return true;
    }
    ref.read(sentenceControllerProvider.notifier).showSentence(sentence);
    ref.invalidate(allSentencesProvider);
    return true;
  }

  /// 別端末（iPhone と iPad など）で進んだ位置とまとめクイズを取り込む。
  ///
  /// 読んでいる位置まで合わせるのは例文の段にいるときだけ。クイズを解いている
  /// 最中に裏のセットを動かすと、解き終えたあとの「次へ」が別の1本を指す。
  /// 例文の差し替えは initState のリスナーが拾う。
  Future<void> _adoptProgressFromOtherDevices() async {
    final adopt = _learningKey.currentState?.isOnSentenceStage ?? true;
    await ref.read(dailySetProvider.notifier).syncFromCloud(adopt: adopt);
    if (!mounted || !adopt) return;
    await _learningKey.currentState?.restoreProgress();
  }

  /// 初回ロードと通知タップ処理を直列化する。
  ///
  /// 並行させると sync() が二重に走り、通知経由で表示した配信例文を
  /// 初回ロード側の loadOrGenerateToday が上書きしてしまう。
  /// 初回起動時は onboarding の push 中に popUntil が走る危険もある。
  Future<void> _loadInitialSentenceThenHandleNotification() async {
    await runInitialLoad(
      load: _checkFirstLaunchAndLoadSentence,
      recover: _recoverAfterInitialLoadFailure,
      markCompleted: () => _initialLoadCompleted = true,
    );
    // 起動時の復元は端末の記録から出す（通信を待たない）。別端末のほうが
    // 先へ進んでいれば、表示してから追いつかせる。
    if (_initialLoadCompleted) unawaited(_adoptProgressFromOtherDevices());

    await _handleInitialNotificationOpen();
    await _maybeShowPremiumTrialStarted();
    await _maybeShowPremiumTrialEnded();
    await _maybeShowLifetimeMigration();
  }

  /// サンプル表示から本人がやり直す導線。起動時と同じ手順（配信の取り込み →
  /// 前回の続き → 生成）をもう一度通す。
  Future<void> _reloadToday() async {
    try {
      await _loadTodaySentence();
    } catch (e) {
      debugPrint('HomeScreen: reload failed: $e');
      await _recoverAfterInitialLoadFailure();
    }
  }

  /// 起動ロードが落ちたときの最後の受け皿。ローカルの最新例文（無ければ空）を出す。
  Future<void> _recoverAfterInitialLoadFailure() async {
    if (!mounted) return;
    if (ref.read(sentenceControllerProvider) is SentenceStateSuccess) return;
    await ref.read(sentenceControllerProvider.notifier).loadMostRecent();
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
    await PaywallScreen.show(context, source: 'onboarding_trial_started');
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
    await ref.read(userDocSnapshotProvider.future);
    if (!mounted) return;

    // 一括配布で配られた人だけが対象。
    if (ref.read(premiumTrialBackfilledAtProvider).valueOrNull == null) return;
    // 配布後に起動しないまま期限が切れた人には、開放を伝えても意味がない。
    // 何も持っていない状態で「開放しました」と言うことになる。
    if (!ref.read(trialActiveProvider)) return;

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
    await ref.read(userDocSnapshotProvider.future);
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
    await PaywallScreen.show(context, source: 'trial_ended');
  }

  /// 月額を買ってくださった方に、買い切りへの無償移行を案内する。
  /// いま継続中の方に加えて、過去に買って期限が切れた方も対象。
  ///
  /// 買い切りプランを出したこと自体を知る機会がここしか無いので、起動時に
  /// 割り込んで伝える。案内は一度だけ（押し損ねた人・移行に失敗した人は
  /// 設定のプラン欄から入り直せる）。
  Future<void> _maybeShowLifetimeMigration() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(AppConfig.prefKeyLifetimeMigrationNotified) ?? false) {
      return;
    }
    // users doc が届く前に読むと、常に「対象外」で素通りしてしまう。
    await ref.read(userDocSnapshotProvider.future);
    if (!mounted) return;

    if (!ref.read(lifetimeMigrationEligibleProvider)) {
      // 対象外（名簿に無い人）にも「案内は済んだ」と記録して閉じる。ここを
      // 開けたままにすると、このリリース後に月額を買った人にまで無償移行が
      // 出てしまう。案内はあくまで、出した時点で続けてくださっていた方向け。
      await prefs.setBool(AppConfig.prefKeyLifetimeMigrationNotified, true);
      return;
    }
    if (ModalRoute.of(context)?.isCurrent != true) return;

    // 出した時点で立てる。移行に失敗しても起動のたびに割り込まない
    //（やり直しは設定から）。
    await prefs.setBool(AppConfig.prefKeyLifetimeMigrationNotified, true);
    await prefs.setBool(AppConfig.prefKeyLifetimeMigrationOffered, true);
    if (!mounted) return;

    await showLifetimeMigrationFlow(
      context,
      migrate: () =>
          ref.read(subscriptionControllerProvider.notifier).migrateToLifetime(),
    );
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
    final delivered =
        await _showDeliveredIfAny(sentenceId: sentenceId, force: true);
    if (!delivered.displayed || !mounted) return;
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

    // 別端末で進んだ位置は後ろで取り込む。待たないのは、通信が遅いあいだ
    // 端末の続きを表示できないほうが困るため。
    unawaited(_adoptProgressFromOtherDevices());

    // 生成中ならスキップ
    final currentState = ref.read(sentenceControllerProvider);
    if (currentState is SentenceStateLoading) {
      return;
    }

    // 裏に回っている間に配信されていれば、それに差し替える
    if ((await _showDeliveredIfAny()).imported) return;

    final data = (await ref.read(userDocSnapshotProvider.future)).data;
    final isGenerated = (data?['daily_sentence_generated'] as bool?) ?? false;

    // 今日の生成済みフラグが立っていて表示成功状態なら、そのまま維持する
    if (isGenerated && currentState is SentenceStateSuccess) {
      return;
    }

    // 日付が変わると daily_sentence_generated は false へ戻る。セットの途中で
    // ここを通ると新しいセットを生成してしまい、開いた瞬間に例文が切り替わって
    // 残りが飛ばされる。消化しきってから次を出す。
    if (!isGenerated && !ref.read(dailySetProvider).isActive) {
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
    // 読み込み元を確かめる前にローディングを立てる。ここから下は配信の取り込みや
    // Firestore の読みで待たされるので、Initial のままだと画面が空に見える。
    ref.read(sentenceControllerProvider.notifier).markLoading();

    // カーソル復元と新着同期を直列化する。復元を投げっぱなしにすると、同期で
    // 開始した新しいセットを古いカーソルが後から上書きする。
    // 復元そのものは controller 側で1回に束ねている。
    await ref.read(dailySetProvider.notifier).restored;

    // 配信例文の取り込みを先に終わらせる。今日ぶんがあればそれが今日の例文なので、
    // 生成もローカル読み込みも走らせない（通知タップかどうかの判定は不要）。
    //
    // 待機列へ回しただけ（queued）のときは何も表示していない。ここで抜けると
    // 起動直後が空表示のままになるので、下の復元へ落とす。
    if ((await _showDeliveredIfAny()).displayed) return;

    // 新着が無ければ、前回閉じた位置の例文をそのまま表示する。「最新の例文」を
    // 読むと、カーソルが2/5なのに本文は5本目という不整合になる。
    final restored = ref.read(dailySetProvider).current;
    if (restored != null) {
      ref.read(sentenceControllerProvider.notifier).showSentence(restored);
      return;
    }

    final data = (await ref.read(userDocSnapshotProvider.future)).data;
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
      LearningScreen(key: _learningKey, onReload: _reloadToday),
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

/// 配信取り込みの結果。
///
/// [displayed] は実際に画面へ出したか。[imported] は表示・待機を問わず新しい
/// 配信を受け取ったか（受け取っていれば、その日の例文は決まっているので
/// 生成もローカル読み込みも要らない）。
typedef DeliveredOutcome = ({bool displayed, bool imported});

const DeliveredOutcome noDelivery = (displayed: false, imported: false);

@visibleForTesting
DeliveredOutcome mergeDeliveredOutcome(DeliveredOutcome a, DeliveredOutcome b) {
  return (
    displayed: a.displayed || b.displayed,
    imported: a.imported || b.imported,
  );
}

/// 起動ロードを実行し、失敗しても「完了」として扱う。
///
/// [markCompleted] を落とすと、復帰時の再ロードも配信・クォータのリスナーも
/// 全て素通りになり、アプリを再起動するまで例文が出ない。失敗こそ、この後の
/// 経路を生かしておく必要がある。[recover] は画面を待たせっぱなしにしない
/// ための受け皿。
@visibleForTesting
Future<void> runInitialLoad({
  required Future<void> Function() load,
  required Future<void> Function() recover,
  required void Function() markCompleted,
}) async {
  try {
    await load();
  } catch (e) {
    debugPrint('HomeScreen: initial load failed: $e');
    try {
      await recover();
    } catch (e) {
      debugPrint('HomeScreen: initial load recovery failed: $e');
    }
  } finally {
    markCompleted();
  }
}

/// 通知を再度開いたとき、消化中の同じセットを先頭へ戻さないための判定。
@visibleForTesting
bool isSameDailySet(DailySetState active, DailySentenceSet delivered) {
  if (!active.isActive) return false;

  // Firestore を読めない通知タップは、ローカルにある通知対象の1本だけを返す。
  // それが消化中セットの一員なら同じセットとして扱い、カーソルを壊さない。
  if (delivered.sentences.length == 1) {
    final deliveredId = delivered.first.id;
    return deliveredId != null &&
        active.sentences.any((sentence) => sentence.id == deliveredId);
  }

  return active.sentences.length == delivered.sentences.length &&
      active.sentences.asMap().entries.every(
            (entry) => entry.value.id == delivered.sentences[entry.key].id,
          );
}

@visibleForTesting
bool shouldAutoLoadAfterSentenceQuotaRefresh({
  required AsyncValue<int>? previous,
  required AsyncValue<int> next,
  required bool dailySentenceGenerated,
  bool hasActiveSet = false,
}) {
  return !dailySentenceGenerated &&
      !hasActiveSet &&
      changedFromNoRemainingToAvailable(previous, next);
}
