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

/// free の1日あたりの例文生成回数。サーバ側の quota.ts と一致させること。
/// premium は無制限なので、対応する定数は持たない（文言側で「無制限」と書く）。
const freeDailySentences = 5;

/// 新規ユーザーに配るプレミアム体験の期間（日）。
/// サーバ側の quota.PremiumTrialDays と一致させること。
const premiumTrialDays = 2;

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
    required this.canChangeMonthlyToLifetime,
    required this.hasChoice,
    required this.plan,
    required this.productLoaded,
  });

  /// 購入ボタンを出すか。加入済みで買い替えも無い人には売らない。
  final bool forSale;
  final bool canChangeMonthlyToLifetime;
  final bool hasChoice;

  /// 購入ボタンで買うプラン。
  final PremiumPlan plan;

  /// 選んでいるプランの商品がストアから引けているか。
  final bool productLoaded;

  bool get lifetimeChosen => plan == PremiumPlan.lifetime;
}

class _PaywallScreenState extends ConsumerState<PaywallScreen> {
  /// 既定は月額。最初の負担が軽い方を初期選択にする。
  PremiumPlan _plan = PremiumPlan.monthly;

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
                    _buildHero(context, ref),
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

    // 年額も買い切りも引けない環境では選択肢が1つしか無い。ラジオも
    // 「このプランで」も出さず、これまでの1本道にする。
    final available = PremiumPlan.values
        .where((plan) => subState.productFor(plan) != null)
        .length;
    final hasChoice = available > 1 && !canChangeMonthlyToLifetime;
    final plan = canChangeMonthlyToLifetime
        ? PremiumPlan.lifetime
        : hasChoice
            ? _plan
            : PremiumPlan.monthly;

    return _Offer(
      forSale: !subState.isPremium || canChangeMonthlyToLifetime,
      canChangeMonthlyToLifetime: canChangeMonthlyToLifetime,
      hasChoice: hasChoice,
      plan: plan,
      productLoaded: subState.productFor(plan) != null,
    );
  }

  /// 表題。アプリの主役の面と同じ深藍で、ここが特別な画面だと示す。
  Widget _buildHero(BuildContext context, WidgetRef ref) {
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
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l10n.paywallTitle,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 14),
                  // 金の細い罫。例文カードと同じ引き方で揃える。
                  Container(
                    height: 1,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [AppColors.gold, Color(0x00C39A4E)],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    l10n.paywallTagline,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  _buildTrialNote(context, ref),
                ],
              ),
            ),
          );
        },
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
    final colorScheme = Theme.of(context).colorScheme;

    if (!offer.forSale) {
      // 加入済みの人には売らない。いま有効だと分かれば足りる。
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
        if (!offer.canChangeMonthlyToLifetime && subState.product != null)
          _buildPlanCard(
            context,
            plan: PremiumPlan.monthly,
            title: L10n.of(context).paywallPlanMonthlyTitle,
            note: L10n.of(context).paywallPlanMonthlyNote,
            price: L10n.of(context).paywallPlanMonthlyPrice(
              subState.product!.price,
            ),
            selectable: offer.hasChoice,
          ),
        if (!offer.canChangeMonthlyToLifetime && subState.yearlyProduct != null)
          _buildPlanCard(
            context,
            plan: PremiumPlan.yearly,
            title: L10n.of(context).paywallPlanYearlyTitle,
            note: L10n.of(context).paywallPlanYearlyNote,
            price: L10n.of(context).paywallPlanYearlyPrice(
              subState.yearlyProduct!.price,
            ),
            selectable: offer.hasChoice,
          ),
        if (subState.lifetimeProduct != null)
          _buildPlanCard(
            context,
            plan: PremiumPlan.lifetime,
            title: L10n.of(context).paywallPlanLifetimeTitle,
            note: L10n.of(context).paywallPlanLifetimeNote,
            price: subState.lifetimeProduct!.price,
            selectable: offer.hasChoice,
          ),
        // 買い切りを選んでいる間は、自動更新の開示文ではなくこちらを出す。
        if (offer.lifetimeChosen) ...[
          const SizedBox(height: 6),
          Text(
            offer.canChangeMonthlyToLifetime
                ? L10n.of(context).paywallMonthlyToLifetimeNote
                : L10n.of(context).paywallLifetimeNote,
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
                    offer.canChangeMonthlyToLifetime
                        ? L10n.of(context).paywallChangeToLifetimeCta
                        : offer.hasChoice
                            ? L10n.of(context).paywallPurchaseCta
                            : L10n.of(context).paywallSubscribe,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: colorScheme.onPrimary,
                        ),
                  ),
          ),
        ],
      ),
    );
  }

  /// プラン1つぶん。名前・更新の有無・価格をこの並びで固定して、2つを縦に
  /// 見比べられるようにする。
  Widget _buildPlanCard(
    BuildContext context, {
    required PremiumPlan plan,
    required String title,
    required String note,
    required String price,
    required bool selectable,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final selected = !selectable || _plan == plan;

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
                    Text(
                      title,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
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

  /// プレミアム体験に触れる一行。
  ///
  /// 体験を持っていないユーザー（期限が無い旧ユーザー）には何も出さない。
  /// ストアの無料トライアルではないので、価格の近くではなく説明側に置く。
  Widget _buildTrialNote(BuildContext context, WidgetRef ref) {
    final expiresAt = ref.watch(premiumTrialExpiresAtProvider).valueOrNull;
    if (expiresAt == null) return const SizedBox.shrink();
    final active = DateTime.now().isBefore(expiresAt);

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Text(
        active
            ? L10n.of(context).paywallTrialActive
            : L10n.of(context).paywallTrialEnded,
        style: Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(color: const Color(0xFFD8BE8A)),
        textAlign: TextAlign.center,
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
