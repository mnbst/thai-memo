/// paywall_screen.dart — プレミアムプラン購入画面（ペイウォール）
///
/// Free ユーザーに対してプレミアムプランの特典を提示し、購入・復元を促す画面。
/// モーダルボトムシートとして表示され、以下の要素で構成される:
///
/// 1. Free / Premium の機能比較テーブル（例文生成回数、クイズ、テーマ数など）
/// 2. 月額価格の表示（ストアから動的に取得した実際の価格）
/// 3. 「プレミアムに登録」ボタン → OS ネイティブの決済シートを起動
/// 4. 「購入を復元」ボタン → 機種変更・再インストール時の復元用
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
import '../../l10n/app_localizations.dart';
import '../../services/firebase_auth_service.dart';
import '../providers/analytics_provider.dart';
import '../providers/pronunciation_quota_provider.dart';
import '../providers/remaining_quota_provider.dart';
import '../providers/subscription_provider.dart';
import '../widgets/sign_in_sheet.dart';
import '../widgets/vocab_score_dialog.dart';

/// 1日あたりの例文生成回数。サーバ側の quota.ts / constants.py と一致させること。
const freeDailySentences = 5;
const premiumDailySentences = 20;

/// プレミアムプランの説明を表示するモーダルボトムシート
class PaywallBottomSheet extends ConsumerWidget {
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
    unawaited(
      container
          .read(subscriptionControllerProvider.notifier)
          .ensureStoreReady()
          .catchError((Object error, StackTrace stackTrace) {
        debugPrint('Failed to warm up store: $error');
      }),
    );
    // 呼び出し元の source を失わないよう、表示前にイベントを確定させる。
    unawaited(analytics.logTapPaywall(source: source));
    unawaited(
      analytics.logScreenView(
        screenName: routeName,
        screenClass: 'PaywallBottomSheet',
      ),
    );

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
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.72,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                controller: scrollController,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // ドラッグハンドル + 閉じるボタン
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          Container(
                            width: 40,
                            height: 4,
                            decoration: BoxDecoration(
                              color: colorScheme.onSurfaceVariant
                                  .withValues(alpha: 0.3),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: SizedBox(
                              width: 28,
                              height: 28,
                              child: IconButton(
                                onPressed: () => Navigator.of(context).pop(),
                                icon: Icon(
                                  Icons.close,
                                  size: 18,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                                padding: EdgeInsets.zero,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // タイトル
                      Text(
                        L10n.of(context).paywallTitle,
                        style:
                            Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: colorScheme.primary,
                                ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        L10n.of(context).paywallTagline,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                        textAlign: TextAlign.center,
                      ),
                      _buildTrialNote(context, ref),
                      const SizedBox(height: 16),
                      _buildMainBenefits(context),
                    ],
                  ),
                ),
              ),
            ),
            _buildPurchaseBar(context, ref),
          ],
        );
      },
    );
  }

  /// 固定購入バー: 価格表示・購入ボタン・復元ボタン・エラー表示
  ///
  /// 既にプレミアムの場合は「加入中」メッセージのみ表示。
  /// product が null（ストアから商品情報を取得できていない）の場合、購入ボタンは無効化される。
  /// 購入を開始する。匿名ユーザーの場合は、復元のため先にサインインを必須とする。
  Future<void> _startPurchase(BuildContext context, WidgetRef ref) async {
    if (FirebaseAuthService.instance.currentUser?.isAnonymous ?? true) {
      final signedIn = await showSignInSheet(
        context,
        title: L10n.of(context).paywallSignInRequired,
        message: L10n.of(context).paywallSignInForPurchase,
      );
      if (!signedIn || !context.mounted) return;
    }
    unawaited(
      ref.read(analyticsServiceProvider).logSubscribe(source: source),
    );
    await ref.read(subscriptionControllerProvider.notifier).purchase();
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

    if (subState.isPremium) {
      return Container(
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(24, 14, 24, 14 + bottomSafeArea),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          border: Border(
            top: BorderSide(color: colorScheme.outlineVariant),
          ),
        ),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            L10n.of(context).paywallActive,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.bold,
                ),
            textAlign: TextAlign.center,
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
      padding: EdgeInsets.fromLTRB(24, 10, 24, 10 + bottomSafeArea),
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
          // 価格表示
          if (subState.product != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                _formatPrice(L10n.of(context), subState.product!.rawPrice,
                    subState.product!.currencyCode),
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                textAlign: TextAlign.center,
              ),
            ),
          // エラーメッセージ
          if (subState.errorMessage != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                subState.errorMessage!,
                style: TextStyle(color: colorScheme.error),
                textAlign: TextAlign.center,
              ),
            ),
          // 購入ボタン
          FilledButton(
            onPressed: subState.isLoading || subState.product == null
                ? null
                : () => _startPurchase(context, ref),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              minimumSize: const Size(double.infinity, 0),
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
                    L10n.of(context).paywallSubscribe,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
                  ),
          ),
          // 自動更新サブスクリプション開示文（iOS: Apple ガイドライン 3.1.2 準拠）
          if (defaultTargetPlatform == TargetPlatform.iOS) ...[
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

  String _formatPrice(L10n l10n, double rawPrice, String currencyCode) {
    if (currencyCode == 'JPY') {
      return l10n.paywallPriceYen('${rawPrice.toInt()}');
    }
    return l10n.paywallPrice(currencyCode, rawPrice.toStringAsFixed(2));
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
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        active
            ? L10n.of(context).paywallTrialActive
            : L10n.of(context).paywallTrialEnded,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildMainBenefits(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final premiumStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: colorScheme.primary,
          fontWeight: FontWeight.bold,
        );

    Widget row({
      required IconData icon,
      required String title,
      required List<Widget> body,
    }) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: colorScheme.primary, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 4),
                ...body,
              ],
            ),
          ),
        ],
      );
    }

    /// Free では何がどこまでで、プレミアムでどうなるかを1行ずつ対比させる。
    Widget benefitRow({
      required IconData icon,
      required String title,
      required String freeText,
      required String premiumText,
    }) {
      return row(
        icon: icon,
        title: title,
        body: [
          Text(
            freeText,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 2),
          Text('→ $premiumText', style: premiumStyle),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          benefitRow(
            icon: Icons.bolt,
            title: L10n.of(context).paywallFeatureQuotaTitle,
            // 例文の回数と語彙スコアの上限を1行にまとめる。どちらも
            // 「どれだけ触れられるか」の話なので、行を分けると差が薄まる。
            freeText: L10n.of(context)
                .paywallFeatureQuotaFree(freeDailySentences,
                    freeVocabScoreLimit),
            premiumText: L10n.of(context)
                .paywallFeatureQuotaPremium(premiumDailySentences),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Divider(height: 1, color: colorScheme.outlineVariant),
          ),
          // 数で示せる2つ（例文・発音）を先に並べる。体験終了ダイアログの
          // 並び（例文→発音）とも揃えている。
          benefitRow(
            icon: Icons.mic_none,
            title: L10n.of(context).paywallFeaturePronunciationTitle,
            freeText: L10n.of(context)
                .paywallFeaturePronunciationFree(freeDailyPronunciationChecks),
            premiumText: L10n.of(context).paywallFeaturePronunciationPremium,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Divider(height: 1, color: colorScheme.outlineVariant),
          ),
          // テーマも回数と同じ対比で見せる。無料は「おまかせ」で届くだけ、
          // プレミアムは自分で選べる、という差がそのまま行になる。
          benefitRow(
            icon: Icons.palette_outlined,
            title: L10n.of(context).paywallFeatureTopicTitle,
            freeText: L10n.of(context).paywallFeatureTopicFree,
            premiumText: L10n.of(context).paywallFeatureTopicPremium,
          ),
        ],
      ),
    );
  }
}
