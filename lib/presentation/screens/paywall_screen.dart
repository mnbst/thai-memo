/// paywall_screen.dart — プレミアムプラン購入画面（ペイウォール）
///
/// Free ユーザーに対してプレミアムプランの特典を提示し、購入・復元を促す画面。
/// 全画面のページとして表示し、購入ボタン以外は1本のスクロールに載せる
/// （ボトムシート＋固定購入バーだと、小さい iPhone で特典が見切れた）:
///
/// 1. 表題カードと特典
/// 2. プラン選択（月額／買い切り。価格はストアから取得した実際の値）
/// 3. 開示文と「購入を復元」・規約・プライバシーポリシー
/// 4. 下端に固定した購入ボタン → OS ネイティブの決済シートを起動
///
/// 【表示トリガー】
/// - 設定画面のアップグレードバナータップ
/// - ホーム画面で例文生成のクォータ超過時
/// - クイズ画面でクイズ生成のレート制限時
///
/// 【関連ファイル】
/// - subscription_provider.dart: 購入状態管理（SubscriptionController）
/// - purchase_service.dart: ストア決済処理
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/app_colors.dart';
import '../../l10n/app_localizations.dart';
import '../../services/firebase_auth_service.dart';
import '../../services/purchase_service.dart';
import '../providers/analytics_provider.dart';
import '../providers/remaining_quota_provider.dart';
import '../providers/subscription_provider.dart';
import '../widgets/sign_in_sheet.dart';

/// free の1日あたりのセット数。サーバ側の quota.FreeDailySentences と一致させること。
/// 1セットの本数は人によって2〜5本なので、本数ではなくセット数で数える。
/// premium は無制限なので、対応する定数は持たない（文言側で「無制限」と書く）。
const freeDailySets = 2;

/// 1.4.12以前のユーザーに互換付与する旧体験の期間（日）。
/// 新規ユーザーの無料期間はストアから取得し、この値は使わない。
/// サーバ側の quota.PremiumTrialDays と一致させること。
const legacyPremiumTrialDays = 2;

/// プレミアムプランの説明を表示する全画面ページ
class PaywallScreen extends ConsumerStatefulWidget {
  static const routeName = 'paywall';

  const PaywallScreen({
    super.key,
    required this.source,
  });

  final String source;

  /// ペイウォールを全画面で開く
  static Future<void> show(
    BuildContext context, {
    String source = 'unknown',
  }) async {
    final container = ProviderScope.containerOf(context, listen: false);
    final analytics = container.read(analyticsServiceProvider);
    // 商品取得の決着を待ってから paywall_view を送る。取得できていなければ
    // 購入ボタンは押せないので、tap_paywall との差が「開いたが買えない」数になる。
    unawaited(
      container
          .read(subscriptionControllerProvider.notifier)
          .ensureStoreReady()
          .catchError((Object error, StackTrace stackTrace) {
        debugPrint('Failed to warm up store: $error');
      }).whenComplete(() {
        unawaited(
          analytics.logPaywallView(
            source: source,
            productLoaded:
                container.read(subscriptionControllerProvider).product != null,
          ),
        );
      }),
    );
    // 呼び出し元の source を失わないよう、表示前にイベントを確定させる。
    unawaited(analytics.logTapPaywall(source: source));
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (context) => PaywallScreen(source: source),
      ),
    );
  }

  @override
  ConsumerState<PaywallScreen> createState() => _PaywallScreenState();
}

/// 画面の状態から決まる「いま何を売るか」。
class _Offer {
  const _Offer({
    required this.forSale,
    required this.changing,
    required this.currentPlan,
    required this.changeTargets,
    required this.hasChoice,
    required this.plan,
    required this.productLoaded,
    required this.selectedTrial,
    required this.headlineTrial,
  });

  /// 購入ボタンを出すか。加入済みで変更先も無い人には売らない。
  final bool forSale;

  /// 加入中の人のプラン変更か（月額⇄年額、サブスク→買い切り）。
  final bool changing;

  /// 加入中の自動更新プラン（iOS の月額・年額）。分からなければ null。
  final PremiumPlan? currentPlan;

  /// 加入中の人が変更できるプラン。
  final List<PremiumPlan> changeTargets;
  final bool hasChoice;

  /// 購入ボタンで買うプラン。
  final PremiumPlan plan;

  /// 選んでいるプランの商品がストアから引けているか。
  final bool productLoaded;

  /// 選んでいるプランの無料トライアル。始められなければ null。
  final StoreTrial? selectedTrial;

  /// 見出しに出す無料トライアル。どのプランでも使えなければ null
  /// （「初回限定」も出さない）。
  final StoreTrial? headlineTrial;

  bool get trial => selectedTrial != null;
  bool get anyTrial => headlineTrial != null;

  bool get lifetimeChosen => plan == PremiumPlan.lifetime;
}

class _PaywallScreenState extends ConsumerState<PaywallScreen> {
  /// 既定は年額。無料トライアルならどちらも最初は0円なので、割安な方を先に見せる。
  /// 年額が引けない環境では [_resolveOffer] が月額へ倒す。
  PremiumPlan _plan = PremiumPlan.yearly;

  String get source => widget.source;

  @override
  Widget build(BuildContext context) {
    final offer = _resolveOffer(ref);
    final bottomSafeArea = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildTopBar(context),
            // 購入ボタン以外は全部ここに載せる。下に固定する物を増やすと、
            // 小さい iPhone で特典の見える範囲が削られて見切れる。
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  AppConfig.screenPadding,
                  4,
                  AppConfig.screenPadding,
                  20 + (offer.forSale ? 0 : bottomSafeArea),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildHero(context, offer),
                    const SizedBox(height: 20),
                    _buildMainBenefits(context),
                    const SizedBox(height: 20),
                    _buildPlanSection(context, ref, offer),
                  ],
                ),
              ),
            ),
            if (offer.forSale) _buildPurchaseButtonBar(context, ref, offer),
          ],
        ),
      ),
    );
  }

  /// 閉じるボタン。中身と一緒にスクロールさせない。
  Widget _buildTopBar(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
        child: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close),
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
        ),
      ),
    );
  }

  /// いま何を売るか。プラン欄と購入ボタンが同じ判定を使う。
  _Offer _resolveOffer(WidgetRef ref) {
    final subState = ref.watch(subscriptionControllerProvider);
    final userData = ref.watch(userDocProvider).valueOrNull;
    final subscription = userData?['subscription'];
    // 月額・年額のどちらでも、ストアの自動更新サブスクを持っている。
    final hasStoreSubscription = subscription is Map &&
        (subscription['platform'] == 'ios' ||
            subscription['platform'] == 'android') &&
        subscription['lifetime'] != true;
    // 無償移行の対象者に買い切りを購入させない。名簿外のサブスク加入者だけ、
    // 有効期限を待たず買い切りへ変更できる。買い切りは現在iOSのみ販売。
    final canChangeMonthlyToLifetime = subState.isPremium &&
        hasStoreSubscription &&
        !ref.watch(lifetimeMigrationEligibleProvider) &&
        subState.lifetimeProduct != null;

    // 加入中の自動更新プラン。月額⇄年額は同じ購読グループなので、もう一方を
    // 買えば Apple が切り替えとして扱う（年額へは即時・月額へは次回更新から）。
    // Android は Play 側の切り替え処理（ChangeSubscriptionParam）が未対応なので
    // 出さない。
    final currentPlan = subState.isPremium &&
            hasStoreSubscription &&
            subscription['platform'] == 'ios'
        ? switch (subscription['product_id']) {
            kProductIdPremiumMonthly => PremiumPlan.monthly,
            kProductIdPremiumYearly => PremiumPlan.yearly,
            _ => null,
          }
        : null;
    final changeTargets = [
      if (currentPlan != null)
        for (final plan in [PremiumPlan.monthly, PremiumPlan.yearly])
          if (plan != currentPlan && subState.productFor(plan) != null) plan,
      if (canChangeMonthlyToLifetime) PremiumPlan.lifetime,
    ];
    final changing = subState.isPremium && changeTargets.isNotEmpty;

    // 年額も買い切りも引けない環境では選択肢が1つしか無い。ラジオも
    // 「このプランで」も出さず、これまでの1本道にする。
    final available = PremiumPlan.values
        .where((plan) => subState.productFor(plan) != null)
        .length;
    final hasChoice = changing ? changeTargets.length > 1 : available > 1;
    final plan = changing
        ? (changeTargets.contains(_plan) ? _plan : changeTargets.first)
        : hasChoice && subState.productFor(_plan) != null
            ? _plan
            : PremiumPlan.monthly;

    // 加入中の人（プラン変更）にトライアルは無い。
    final trialForSale = !subState.isPremium;

    return _Offer(
      forSale: !subState.isPremium || changing,
      changing: changing,
      currentPlan: currentPlan,
      changeTargets: changeTargets,
      hasChoice: hasChoice,
      plan: plan,
      productLoaded: subState.productFor(plan) != null,
      selectedTrial: trialForSale ? subState.trials[plan] : null,
      // 無料体験の見出しは、購入ボタンが実際に開始するプランにだけ連動させる。
      // 別プランの特典へフォールバックすると、買い切りや対象外プランを選んだ
      // 状態でも「無料体験」と表示され、実際の即時請求と食い違ってしまう。
      headlineTrial: trialForSale ? subState.trials[plan] : null,
    );
  }

  /// 表題。アプリの主役の面と同じ深藍で、ここが特別な画面だと示す。
  Widget _buildHero(BuildContext context, _Offer offer) {
    final l10n = L10n.of(context);
    return Theme(
      data: Theme.of(context).copyWith(colorScheme: AppColors.onIndigo),
      child: Builder(
        builder: (context) {
          final theme = Theme.of(context);
          final cs = theme.colorScheme;
          return Card(
            color: AppColors.indigo,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppConfig.heroBorderRadius),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (offer.anyTrial) ...[
                    Center(child: _buildTrialBadge(context)),
                    const SizedBox(height: 10),
                  ],
                  // トライアルを出すときは見出しを1本にする。「プレミアムプラン」と
                  // 「無料でおためし」を並べると、どちらが主役か分からなくなる。
                  Text(
                    offer.anyTrial
                        ? l10n.paywallTrialHeadline(offer.headlineTrial!.days)
                        : l10n.paywallTitle,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// 「初回限定」。深藍の上で目に入るよう、金の地に濃い文字で置く。
  Widget _buildTrialBadge(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.gold,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        L10n.of(context).paywallTrialBadge,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.indigo,
            ),
      ),
    );
  }

  /// 購入を開始する。匿名ユーザーの場合は、復元のため先にサインインを必須とする。
  Future<void> _startPurchase(
    BuildContext context,
    WidgetRef ref, {
    required PremiumPlan plan,
  }) async {
    if (FirebaseAuthService.instance.currentUser?.isAnonymous ?? true) {
      final signedIn = await showSignInSheet(
        context,
        title: L10n.of(context).paywallSignInRequired,
        message: L10n.of(context).paywallSignInForPurchase,
      );
      if (!signedIn || !context.mounted) return;
    }
    unawaited(
      ref.read(analyticsServiceProvider).logSubscribe(
            source:
                plan == PremiumPlan.monthly ? source : '${source}_${plan.name}',
          ),
    );
    await ref
        .read(subscriptionControllerProvider.notifier)
        .purchase(plan: plan);
  }

  /// 購入を復元する。匿名ユーザーの場合は先にサインインを必須とする。
  Future<void> _startRestore(BuildContext context, WidgetRef ref) async {
    if (FirebaseAuthService.instance.currentUser?.isAnonymous ?? true) {
      final signedIn = await showSignInSheet(
        context,
        title: L10n.of(context).paywallSignInRequired,
        message: L10n.of(context).paywallSignInForRestore,
      );
      if (!signedIn || !context.mounted) return;
    }
    await ref.read(subscriptionControllerProvider.notifier).restore();
  }

  /// プラン選択・開示文・復元と規約へのリンク。スクロールの中に置く。
  ///
  /// 既にプレミアムの場合は「加入中」メッセージのみ表示。
  Widget _buildPlanSection(BuildContext context, WidgetRef ref, _Offer offer) {
    final subState = ref.watch(subscriptionControllerProvider);

    if (!offer.forSale) {
      // 加入済みの人には売らない。いま有効だと分かれば足りる。
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildActiveBadge(context),
          if (_lifetimeWithRenewingSubscription(ref)) ...[
            const SizedBox(height: 12),
            _buildCancelSubscriptionNotice(context),
          ],
        ],
      );
    }
    return _buildChoosablePlanSection(context, ref, offer, subState);
  }

  /// 「プレミアムプランに加入中です」。
  Widget _buildActiveBadge(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.gold.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppConfig.buttonBorderRadius),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.42)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.workspace_premium_outlined,
              size: 20, color: AppColors.goldInk),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              L10n.of(context).paywallActive,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF7A5E22),
                    fontWeight: FontWeight.w700,
                  ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  /// 買い切りを持っているのに、サブスクの自動更新が続いているか（iOS）。
  ///
  /// 買い切りはサブスクとは別の商品なので、買ってもサブスクは自動で
  /// 解約されない。放っておくと両方に課金され続ける。
  bool _lifetimeWithRenewingSubscription(WidgetRef ref) {
    final subscription =
        ref.watch(userDocProvider).valueOrNull?['subscription'];
    return subscription is Map &&
        subscription['lifetime'] == true &&
        subscription['platform'] == 'ios' &&
        subscription['auto_renewing'] == true &&
        subscription['status'] == 'active';
  }

  /// サブスクの解約を促す。Apple の購読管理画面を直接開く。
  Widget _buildCancelSubscriptionNotice(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppConfig.buttonBorderRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.paywallCancelSubscriptionNote,
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: () => launchUrl(
              Uri.parse(AppConfig.appStoreSubscriptionsUrl),
              mode: LaunchMode.externalApplication,
            ),
            child: Text(l10n.paywallManageSubscriptions),
          ),
        ],
      ),
    );
  }

  /// 売るプランを選ぶ欄（新規購入とプラン変更）。
  Widget _buildChoosablePlanSection(
    BuildContext context,
    WidgetRef ref,
    _Offer offer,
    SubscriptionState subState,
  ) {
    final colorScheme = Theme.of(context).colorScheme;

    Widget legalLink({
      required String label,
      required VoidCallback? onPressed,
    }) {
      return TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          minimumSize: Size.zero,
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                decoration: TextDecoration.underline,
              ),
        ),
      );
    }

    Widget separator() {
      return Text(
        '|',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurface.withValues(alpha: 0.4),
            ),
      );
    }

    final noteStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: colorScheme.onSurface.withValues(alpha: 0.6),
          height: 1.25,
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // プラン選択。月額・年額・買い切りを同じ形で並べ、価格と「更新があるか」を
        // 縦に見比べられるようにする。ボタンを2つ並べると、どちらが何円で
        // 何が違うのかが読み取れなかった。
        // 商品が引けていない間は月額カードも出さない。価格が空のカードを
        // 残すと「買えない購入項目が並んでいる」状態になり、App Review で
        // Guideline 2.1(b) を取られる。買い切り側と同じ null ガードにする。
        // プラン一覧の取得中は、カードの代わりにローディングを出す。
        if (subState.isLoadingProducts && subState.product == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          ),
        if (_showsCard(offer, PremiumPlan.monthly) && subState.product != null)
          _buildPlanCard(
            context,
            offer: offer,
            plan: PremiumPlan.monthly,
            title: L10n.of(context).paywallPlanMonthlyTitle,
            note: L10n.of(context).paywallPlanMonthlyNote,
            price: L10n.of(context).paywallPlanMonthlyPrice(
              subState.product!.price,
            ),
          ),
        if (_showsCard(offer, PremiumPlan.yearly) &&
            subState.yearlyProduct != null)
          _buildPlanCard(
            context,
            offer: offer,
            plan: PremiumPlan.yearly,
            title: L10n.of(context).paywallPlanYearlyTitle,
            note: L10n.of(context).paywallPlanYearlyNote,
            price: L10n.of(context).paywallPlanYearlyPrice(
              subState.yearlyProduct!.price,
            ),
            badge: _yearlySavingPercent(subState) == null
                ? null
                : L10n.of(context)
                    .paywallPlanYearlySave(_yearlySavingPercent(subState)!),
          ),
        if (_showsCard(offer, PremiumPlan.lifetime) &&
            subState.lifetimeProduct != null)
          _buildPlanCard(
            context,
            offer: offer,
            plan: PremiumPlan.lifetime,
            title: L10n.of(context).paywallPlanLifetimeTitle,
            note: L10n.of(context).paywallPlanLifetimeNote,
            price: subState.lifetimeProduct!.price,
          ),
        // 買い切りを選んでいる間は、自動更新の開示文ではなくこちらを出す。
        if (offer.lifetimeChosen) ...[
          const SizedBox(height: 6),
          Text(
            offer.changing
                ? L10n.of(context).paywallMonthlyToLifetimeNote
                : L10n.of(context).paywallLifetimeNote,
            style: noteStyle,
          ),
        ],
        // 月額⇄年額はいつ切り替わるかが逆向きで違うので、選んだ向きの分だけ書く。
        if (offer.changing && !offer.lifetimeChosen) ...[
          const SizedBox(height: 6),
          Text(
            offer.plan == PremiumPlan.yearly
                ? L10n.of(context).paywallChangeToYearlyNote
                : L10n.of(context).paywallChangeToMonthlyNote,
            style: noteStyle,
          ),
        ],
        // 自動更新サブスクリプション開示文（iOS: Apple ガイドライン 3.1.2 準拠）
        if (!offer.lifetimeChosen &&
            defaultTargetPlatform == TargetPlatform.iOS) ...[
          const SizedBox(height: 6),
          Text(L10n.of(context).paywallLegal, style: noteStyle),
        ],
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 2,
          children: [
            legalLink(
              label: L10n.of(context).paywallRestore,
              onPressed:
                  subState.isLoading ? null : () => _startRestore(context, ref),
            ),
            separator(),
            legalLink(
              label: L10n.of(context).settingsTerms,
              onPressed: () =>
                  launchUrl(Uri.parse(AppConfig.termsOfServiceUrl)),
            ),
            separator(),
            legalLink(
              label: L10n.of(context).settingsPrivacyPolicy,
              onPressed: () => launchUrl(Uri.parse(AppConfig.privacyPolicyUrl)),
            ),
          ],
        ),
      ],
    );
  }

  /// 下端に固定する購入ボタン。選んでいるプランをそのまま買う。
  ///
  /// エラーは押した場所の近くに出す。product が null（ストアから商品情報を
  /// 取得できていない）の場合、購入ボタンは無効化される。
  Widget _buildPurchaseButtonBar(
    BuildContext context,
    WidgetRef ref,
    _Offer offer,
  ) {
    final subState = ref.watch(subscriptionControllerProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final bottomSafeArea = MediaQuery.paddingOf(context).bottom;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(AppConfig.screenPadding, 12,
          AppConfig.screenPadding, 12 + bottomSafeArea),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          top: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (subState.errorMessage != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                subState.errorMessage!,
                style: TextStyle(color: colorScheme.error),
                textAlign: TextAlign.center,
              ),
            ),
          FilledButton(
            onPressed: subState.isLoading || !offer.productLoaded
                ? null
                : () => _startPurchase(context, ref, plan: offer.plan),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 15),
              minimumSize: const Size(double.infinity, 0),
              shape: RoundedRectangleBorder(
                borderRadius:
                    BorderRadius.circular(AppConfig.buttonBorderRadius),
              ),
            ),
            child: subState.isLoading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    // 購入を開始するボタンなので、何が起きるか一読で分かる言い方にする
                    // （情緒的なコピーは上部のタイトル・比較表で担う）。
                    offer.changing
                        ? switch (offer.plan) {
                            PremiumPlan.lifetime =>
                              L10n.of(context).paywallChangeToLifetimeCta,
                            PremiumPlan.yearly =>
                              L10n.of(context).paywallChangeToYearlyCta,
                            PremiumPlan.monthly =>
                              L10n.of(context).paywallChangeToMonthlyCta,
                          }
                        : offer.trial
                            ? L10n.of(context)
                                .paywallTrialCta(offer.selectedTrial!.days)
                            : offer.hasChoice
                                ? L10n.of(context).paywallPurchaseCta
                                : L10n.of(context).paywallSubscribe,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: colorScheme.onPrimary,
                        ),
                  ),
          ),
          // 無料期間のあと何円かかるかをボタンのすぐ下に書く
          // （App Review Guideline 3.1.2: トライアル後の請求額を明示する）。
          if (offer.trial && offer.productLoaded)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _trialTerms(context, subState, offer),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
    );
  }

  /// 年額を月額12か月ぶんと比べた割引率（%）。比べられない・差が小さいときは null。
  int? _yearlySavingPercent(SubscriptionState subState) {
    final monthly = subState.product;
    final yearly = subState.yearlyProduct;
    if (monthly == null || yearly == null) return null;
    if (monthly.currencyCode != yearly.currencyCode) return null;
    final fullPrice = monthly.rawPrice * 12;
    if (fullPrice <= 0) return null;
    // 切り捨てにする。四捨五入で実際より大きく言わない。
    final percent = ((1 - yearly.rawPrice / fullPrice) * 100).floor();
    return percent >= 5 ? percent : null;
  }

  String _trialTerms(
    BuildContext context,
    SubscriptionState subState,
    _Offer offer,
  ) {
    final l10n = L10n.of(context);
    final price = subState.productFor(offer.plan)!.price;
    final days = offer.selectedTrial!.days;
    return offer.plan == PremiumPlan.yearly
        ? l10n.paywallTrialTermsYearly(days, price)
        : l10n.paywallTrialTermsMonthly(days, price);
  }

  /// プラン1つぶん。名前・更新の有無・価格をこの並びで固定して、2つを縦に
  /// 見比べられるようにする。
  /// プラン変更のときは、今のプランと変更先だけを並べる。
  bool _showsCard(_Offer offer, PremiumPlan plan) =>
      !offer.changing ||
      plan == offer.currentPlan ||
      offer.changeTargets.contains(plan);

  Widget _buildPlanCard(
    BuildContext context, {
    required _Offer offer,
    required PremiumPlan plan,
    required String title,
    required String note,
    required String price,
    String? badge,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    // 今のプランは選べない。並べるのは「どこから変えるのか」を見せるため。
    final current = offer.changing && plan == offer.currentPlan;
    final selectable = offer.hasChoice && !current;
    final selected = !current && plan == offer.plan;
    if (current) badge = L10n.of(context).paywallPlanCurrent;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: selectable ? () => setState(() => _plan = plan) : null,
        borderRadius: BorderRadius.circular(AppConfig.buttonBorderRadius),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: selected && selectable
                ? AppColors.gold.withValues(alpha: 0.10)
                : cs.surface,
            borderRadius: BorderRadius.circular(AppConfig.buttonBorderRadius),
            border: Border.all(
              color: selected ? AppColors.gold : cs.outlineVariant,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              if (selectable) ...[
                Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: 20,
                  color: selected ? AppColors.goldInk : cs.outline,
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        if (badge != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.gold.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              badge,
                              style: theme.textTheme.labelSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: AppColors.goldInk,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      note,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(
                price,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 何がどう変わるかを3つだけ並べる。
  ///
  /// Free の現状 → プレミアムの姿、の対比を1行ずつ。金は「増える側」
  /// にだけ使い、いま持っているものは沈めて置く。
  Widget _buildMainBenefits(BuildContext context) {
    final l10n = L10n.of(context);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // テーマを先頭に置く。「自分で選べる」が一番わかりやすい変化なので、
          // ここから読ませる。
          _buildBenefitRow(
            context,
            icon: Icons.local_offer_outlined,
            title: l10n.paywallFeatureTopicTitle,
            premiumText: l10n.paywallFeatureTopicPremium,
          ),
          const Divider(
            height: 1,
            indent: AppConfig.defaultPadding,
            endIndent: AppConfig.defaultPadding,
          ),
          _buildBenefitRow(
            context,
            icon: Icons.menu_book_outlined,
            title: l10n.paywallFeatureQuotaTitle,
            // 例文の回数と語彙スコアの上限を1行にまとめる。どちらも
            // 「どれだけ触れられるか」の話なので、行を分けると差が薄まる。
            premiumText: l10n.paywallFeatureQuotaPremium,
          ),
        ],
      ),
    );
  }

  /// 特典1つぶん。見出し（太字）と、プレミアムで何が変わるか（金）の2行だけ。
  ///
  /// free の値を並べていたが、プランの比較は下の選択カードの仕事になった。
  /// ここで二重に比べさせると、読む量が増えるわりに差が薄まる。
  Widget _buildBenefitRow(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String premiumText,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22, color: AppColors.goldInk),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodyLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(
                  premiumText,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.goldInk,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
