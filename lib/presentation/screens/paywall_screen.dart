/// paywall_screen.dart — プレミアムプラン購入画面（ペイウォール）
///
/// Free ユーザーに対してプレミアムプランの特典を提示し、購入・復元を促す画面。
/// モーダルボトムシートとして表示され、以下の要素で構成される:
///
/// 1. Free / Premium の機能比較テーブル（例文生成回数、クイズ、テーマ数など）
/// 2. 月額価格の表示（ストアから動的に取得した実際の価格）
/// 3. 「プレミアムに登録」ボタン（月額）→ OS ネイティブの決済シートを起動
/// 4. 「買い切り」ボタン（iOSのみ。商品が引けた時だけ出す）
/// 5. 「購入を復元」ボタン → 機種変更・再インストール時の復元用
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

/// プレミアムプランの説明を表示するモーダルボトムシート
class PaywallBottomSheet extends ConsumerStatefulWidget {
  static const routeName = 'paywall';

  const PaywallBottomSheet({
    super.key,
    required this.source,
  });

  final String source;

  /// ボトムシートを表示する
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
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => PaywallBottomSheet(source: source),
    );
  }

  @override
  ConsumerState<PaywallBottomSheet> createState() =>
      _PaywallBottomSheetState();
}

/// 選べるプラン。どちらも付与される権利は同じ premium で、支払い方だけが違う。
enum _Plan { monthly, lifetime }

class _PaywallBottomSheetState extends ConsumerState<PaywallBottomSheet> {
  /// 既定は月額。最初の負担が軽い方を初期選択にする。
  _Plan _plan = _Plan.monthly;

  String get source => widget.source;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      // 購入バーがプラン2枚ぶん高い。特典が見切れない高さにしておく。
      initialChildSize: 0.86,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            _buildHandle(context),
            Expanded(
              child: SingleChildScrollView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(
                  AppConfig.screenPadding,
                  4,
                  AppConfig.screenPadding,
                  20,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildHero(context, ref),
                    const SizedBox(height: 20),
                    _buildMainBenefits(context),
                  ],
                ),
              ),
            ),
            _buildPurchaseBar(context, ref),
          ],
        );
      },
    );
  }

  /// ドラッグハンドルと閉じる。中身と一緒にスクロールさせない。
  Widget _buildHandle(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 0),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: cs.onSurfaceVariant.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close, size: 20),
              color: cs.onSurfaceVariant,
              visualDensity: VisualDensity.compact,
            ),
          ),
        ],
      ),
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

  /// 固定購入バー: 価格表示・購入ボタン・復元ボタン・エラー表示
  ///
  /// 既にプレミアムの場合は「加入中」メッセージのみ表示。
  /// product が null（ストアから商品情報を取得できていない）の場合、購入ボタンは無効化される。
  /// 購入を開始する。匿名ユーザーの場合は、復元のため先にサインインを必須とする。
  Future<void> _startPurchase(
    BuildContext context,
    WidgetRef ref, {
    bool lifetime = false,
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
            source: lifetime ? '${source}_lifetime' : source,
          ),
    );
    await ref
        .read(subscriptionControllerProvider.notifier)
        .purchase(lifetime: lifetime);
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

  Widget _buildPurchaseBar(BuildContext context, WidgetRef ref) {
    final subState = ref.watch(subscriptionControllerProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final bottomSafeArea = MediaQuery.paddingOf(context).bottom;

    // 買い切りを売っていない環境（Android・商品が引けない時）では選択肢が
    // 1つしか無い。ラジオも「このプランで」も出さず、これまでの1本道にする。
    final hasChoice = subState.lifetimeProduct != null;
    final lifetimeChosen = hasChoice && _plan == _Plan.lifetime;
    final selectedProduct =
        lifetimeChosen ? subState.lifetimeProduct : subState.product;

    if (subState.isPremium) {
      return Container(
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(AppConfig.screenPadding, 14,
            AppConfig.screenPadding, 14 + bottomSafeArea),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          border: Border(
            top: BorderSide(color: colorScheme.outlineVariant),
          ),
        ),
        // 加入済みの人には売らない。いま有効だと分かれば足りる。
        child: Container(
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

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(AppConfig.screenPadding, 12,
          AppConfig.screenPadding, 10 + bottomSafeArea),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          top: BorderSide(color: colorScheme.outlineVariant),
        ),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // プラン選択。月額と買い切りを同じ形で並べ、価格と「更新があるか」を
          // 縦に見比べられるようにする。ボタンを2つ並べると、どちらが何円で
          // 何が違うのかが読み取れなかった。
          _buildPlanCard(
            context,
            plan: _Plan.monthly,
            title: L10n.of(context).paywallPlanMonthlyTitle,
            note: L10n.of(context).paywallPlanMonthlyNote,
            price: subState.product == null
                ? ''
                : L10n.of(context).paywallPlanMonthlyPrice(
                    subState.product!.price,
                  ),
            selectable: hasChoice,
          ),
          if (subState.lifetimeProduct != null)
            _buildPlanCard(
              context,
              plan: _Plan.lifetime,
              title: L10n.of(context).paywallPlanLifetimeTitle,
              note: L10n.of(context).paywallPlanLifetimeNote,
              price: subState.lifetimeProduct!.price,
              selectable: hasChoice,
            ),
          // エラーメッセージ
          if (subState.errorMessage != null)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 8),
              child: Text(
                subState.errorMessage!,
                style: TextStyle(color: colorScheme.error),
                textAlign: TextAlign.center,
              ),
            ),
          const SizedBox(height: 4),
          // 購入ボタン。選んでいるプランをそのまま買う。
          FilledButton(
            onPressed: subState.isLoading || selectedProduct == null
                ? null
                : () => _startPurchase(context, ref, lifetime: lifetimeChosen),
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
                    hasChoice
                        ? L10n.of(context).paywallPurchaseCta
                        : L10n.of(context).paywallSubscribe,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: Theme.of(context).colorScheme.onPrimary,
                        ),
                  ),
          ),
          // 買い切りを選んでいる間は、自動更新の開示文ではなくこちらを出す。
          if (lifetimeChosen) ...[
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: Text(
                L10n.of(context).paywallLifetimeNote,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurface.withValues(alpha: 0.6),
                      height: 1.25,
                    ),
                textAlign: TextAlign.left,
              ),
            ),
          ],
          // 自動更新サブスクリプション開示文（iOS: Apple ガイドライン 3.1.2 準拠）
          if (!lifetimeChosen &&
              defaultTargetPlatform == TargetPlatform.iOS) ...[
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: Text(
                L10n.of(context).paywallLegal,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurface.withValues(alpha: 0.6),
                      height: 1.25,
                    ),
                textAlign: TextAlign.left,
              ),
            ),
          ],
          const SizedBox(height: 2),
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 2,
            children: [
              legalLink(
                label: L10n.of(context).paywallRestore,
                onPressed: subState.isLoading
                    ? null
                    : () => _startRestore(context, ref),
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
                onPressed: () =>
                    launchUrl(Uri.parse(AppConfig.privacyPolicyUrl)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// プラン1つぶん。名前・更新の有無・価格をこの並びで固定して、2つを縦に
  /// 見比べられるようにする。
  Widget _buildPlanCard(
    BuildContext context, {
    required _Plan plan,
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
